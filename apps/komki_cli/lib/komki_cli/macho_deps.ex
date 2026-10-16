defmodule KomkiCli.MachODeps do
  @moduledoc """
  otool-basierter Mach-O-Dependency-Scanner fuer das llama-server-Profil.

  Der Scanner zieht aus einem Mach-O-Binaer:

    * die deklarierten Deps (`otool -L`),
    * die LC_RPATH-Eintraege fuer die @rpath-Aufloesung (`otool -l`),
    * die transitiven Deps (rekursiver otool-Walk),

  und liefert je aufgeloester Dep das deklarierte UND das kanonische
  Pfadverzeichnis (Pfadform-Cave in beide Richtungen — exp6: Regeln nur in
  kanonischer Form matchen nicht) sowie pro Dep-Verzeichnis dessen
  Geschwister-libexec, wenn vorhanden (ggml-Backend-Scan-Ort: dort liegen
  die Backend-Bundles libggml-cpu-apple_m*.so, libggml-metal.so; ohne das
  bleibt die Backend-Registry leer — exp14).

  Aufrufer: `KomkiCli.Profile.generate_llama/1` (dylib-Baum-Regelschicht).

  Fallback: otool fehlt oder Datei unlesbar -> [] (CI-Linux; das Profil
  bleibt generierbar).

  Belege: Experimentserie 14.10.2026, exp6/exp7/exp14 (Tickets
  #100/#111); Nachweis-Konsolidierung:
  `docs/research/2026-10-14-llama-server-confinement.md`.
  """

  alias KomkiCli.Config

  # Dylib-Verzeichnisse des llama-server-Binaers: rekursiver otool-Walk.
  # - otool -L liefert die deklarierten Deps (dyld oeffnet genau diese Pfadformen);
  # - otool -l liefert die LC_RPATH-Eintraege fuer @rpath-Aufloesung;
  # - transitive Deps werden mitgegangen (Fund: libomp via libggml-base);
  # - je aufgeloester Dep: dirname(deklariert) UND dirname(canonical) (Pfadform-Cave
  #   in beide Richtungen — exp6: Regeln nur in kanonischer Form matchen nicht);
  # - pro Dep-Verzeichnis dessen Geschwister-libexec, wenn vorhanden (ggml legt
  #   dort die Backend-Bundles ab: libggml-cpu-apple_m*.so, libggml-metal.so;
  #   ohne das bleibt die Backend-Registry leer — exp14);
  # - otool fehlend oder Datei unlesbar: [] (CI-Linux; Profil bleibt generierbar).
  @doc """
  Dylib-Verzeichnisse des Binaers samt libexec-Geschwistern; Details zur
  Methodik im Moduledoc und im Kommentar unten.
  """
  @spec dylib_dirs(String.t()) :: [String.t()]
  def dylib_dirs(bin) do
    if System.find_executable("otool") == nil or not File.exists?(bin) do
      []
    else
      # queue = [bin], visited leer — das Bin wird beim ersten Durchlauf
      # verarbeitet und erst dann als besucht markiert (Seed-Fund: ein
      # vorbelegtes visited skipped den Root und leert die Queue sofort;
      # die Dep-Liste blieb leer). Accumulatoren als einfache Listen:
      # dialyzer sieht MapSet.t() in den rekursiven Positionen als opaken
      # Term mit auseinanderlaufenden Subtypen (call_without_opaque,
      # Verify-Fund); die Mengen sind winzig, uniq/sort sitzt am Ende.
      bin
      |> dylib_walk([bin], [], [])
      |> libexec_forms()
    end
  end

  defp otool_output(args) do
    case System.find_executable("otool") do
      nil ->
        nil

      otool ->
        case System.cmd(otool, args, stderr_to_stdout: true) do
          {out, 0} -> out
          _ -> nil
        end
    end
  end

  defp dylib_walk(_bin, [], _visited, dirs), do: dirs

  defp dylib_walk(bin, [macho | queue], visited, dirs) do
    canonical_macho = Config.canonical(macho)

    if canonical_macho in visited do
      dylib_walk(bin, queue, visited, dirs)
    else
      deps = otool_deps(macho)
      rpaths = otool_rpaths(macho)

      {queue, dirs} =
        Enum.reduce(deps, {queue, dirs}, fn dep, {acc_queue, acc_dirs} ->
          dep_dirs(dep, rpaths, macho, bin, acc_queue, acc_dirs)
        end)

      dylib_walk(bin, queue, [canonical_macho | visited], dirs)
    end
  end

  defp dep_dirs(dep, rpaths, macho, bin, queue, dirs) do
    case resolve_dep(dep, rpaths, macho, bin) do
      :skip ->
        {queue, dirs}

      {:dep, declared, resolved} ->
        # Rohform des deklarierten Verzeichnisses behalten (dyld oeffnet genau
        # diese Pfadform — Pfadform-Cave exp6) plus die kanonische Form.
        dirs = Enum.uniq([Path.dirname(declared) | dirs])

        if resolved != nil do
          dirs = Enum.uniq([Config.canonical(Path.dirname(resolved)) | dirs])
          {queue ++ [resolved], dirs}
        else
          {queue, dirs}
        end
    end
  end

  defp resolve_dep(dep, rpaths, macho, bin) do
    cond do
      String.starts_with?(dep, "@rpath/") ->
        rpath_dep(dep, rpaths, macho, bin)

      String.starts_with?(dep, "/usr/lib") or String.starts_with?(dep, "/System/Library") ->
        # Basis-Layer deckt die System-Haeuser ab; auch nicht rekursieren.
        :skip

      String.starts_with?(dep, "@executable_path/") or String.starts_with?(dep, "@loader_path/") ->
        loader_dep(dep, macho, bin)

      String.starts_with?(dep, "/") ->
        {:dep, dep, maybe_canonical(dep)}

      true ->
        :skip
    end
  end

  defp rpath_dep(dep, rpaths, macho, bin) do
    rest = String.replace_prefix(dep, "@rpath/", "")

    rpaths
    |> Enum.flat_map(&rpath_roots(&1, macho, bin))
    |> Enum.map(&Path.join(&1, rest))
    |> Enum.find_value(:skip, fn candidate ->
      resolved = maybe_canonical(candidate)
      resolved && {:dep, candidate, resolved}
    end)
  end

  # RPATH-Werte sind selbst loader-relativ: llama.cpp 0.6.0 pinnt
  # "@loader_path/../lib" (Review-Fund: ohne diese Expansion bleiben alle
  # @rpath-Deps unloesbar und der Eigenbau-Lib-Baum faellt aus dem Profil).
  # @loader_path bezieht sich auf das gerade geladene Mach-O, @executable_path
  # auf die Root-Binary; lexikalische Normalisierung via Path.expand.
  defp rpath_roots(rpath, macho, bin) do
    cond do
      String.starts_with?(rpath, "@loader_path/") ->
        [Path.expand(String.replace_prefix(rpath, "@loader_path/", ""), Path.dirname(macho))]

      String.starts_with?(rpath, "@executable_path/") ->
        [Path.expand(String.replace_prefix(rpath, "@executable_path/", ""), Path.dirname(bin))]

      true ->
        [rpath]
    end
  end

  defp loader_dep(dep, macho, bin) do
    rest =
      dep
      |> String.replace_prefix("@loader_path/", "")
      |> String.replace_prefix("@executable_path/", "")

    # Loader-Verzeichnis zuerst, dann das Bin-Verzeichnis (@executable_path).
    candidates = [Path.join(Path.dirname(macho), rest), Path.join(Path.dirname(bin), rest)]

    Enum.find_value(candidates, :skip, fn candidate ->
      resolved = maybe_canonical(candidate)
      resolved && {:dep, candidate, resolved}
    end)
  end

  defp maybe_canonical(path) do
    if File.exists?(path), do: Config.canonical(path), else: nil
  end

  # Deps aus `otool -L`: Kopfzeile (Binaer-Selbstname) weg, pro Zeile das erste
  # Whitespace-Token = der deklarierte Installationspfad. otool rückt Dep-Zeilen
  # mit Tab ein — erst trimmen, sonst startet jedes Token mit "\t" und fällt
  # in resolve_dep durch alle Pfad-Präfixe (Review-Fund: leere Dep-Liste).
  defp otool_deps(macho) do
    case otool_output(["-L", macho]) do
      nil ->
        []

      out ->
        out
        |> String.split("\n")
        |> Enum.drop(1)
        |> Enum.map(&first_token/1)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp first_token(line), do: line |> String.trim() |> String.split(" ") |> List.first()

  # LC_RPATH-Eintraege aus `otool -l`: nach "cmd LC_RPATH" folgt (hinter
  # cmdsize) die "path"-Zeile; Reihenfolge wie gedruckt.
  defp otool_rpaths(macho) do
    case otool_output(["-l", macho]) do
      nil -> []
      out -> otool_rpaths_scan(String.split(out, "\n"), [])
    end
  end

  defp otool_rpaths_scan([], acc), do: Enum.reverse(acc)

  defp otool_rpaths_scan([line | rest], acc) do
    if String.trim(line) == "cmd LC_RPATH" do
      otool_rpath_value(rest, acc)
    else
      otool_rpaths_scan(rest, acc)
    end
  end

  defp otool_rpath_value([], acc), do: Enum.reverse(acc)

  defp otool_rpath_value([line | rest], acc) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(trimmed, "path ") ->
        value = String.replace_prefix(trimmed, "path ", "")
        otool_rpaths_scan(rest, [rpath_value(value) | acc])

      String.starts_with?(trimmed, "cmd ") or String.starts_with?(trimmed, "Load command") ->
        # Naechster Load-Command-Block ohne gefundene path-Zeile: zurueck zum
        # Header-Scan (unvollstaendiger RPATH-Block).
        otool_rpaths_scan([line | rest], acc)

      true ->
        # Zwischenfeld (cmdsize u.a.) im selben RPATH-Block: weitersuchen —
        # die path-Zeile folgt erst danach (Review-Fund: Fruehrueckkehr zum
        # Header-Scan uebersprang sie und liess alle @rpath-Deps unloesbar).
        otool_rpath_value(rest, acc)
    end
  end

  defp rpath_value(value), do: value |> String.split(" (", parts: 2) |> List.first()

  # Geschwister-libexec je Dep-Verzeichnis (ggml-Backend-Scan-Ort); beide
  # Pfadformen bleiben stehen, wenn kanonisch und deklariert auseinanderlaufen.
  defp libexec_forms(dirs) do
    (dirs ++ Enum.flat_map(dirs, &dir_libexec_forms/1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp dir_libexec_forms(dir) do
    declared = Path.join(Path.dirname(dir), "libexec")
    sibling = Config.canonical(declared)

    if File.exists?(sibling) do
      Enum.uniq([sibling, declared])
    else
      []
    end
  end
end
