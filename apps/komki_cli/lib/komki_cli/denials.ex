defmodule KomkiCli.Denials do
  @moduledoc """
  Denial-Capture fuer `komki run --capture-denials` (Ticket #125).

  Die Grant-Discovery-Disziplin der Confinement-Arbeit lief bisher manuell:
  Lauf unter der Grenze, `log show` nach `deny`-Zeilen filtern, Grant
  ergaenzen. Dieses Modul sammelt die Denials eines pi-Lauffensters aus dem
  Unified Log und schreibt daraus einen versionierten Bericht unter
  `<base>/denials/`. Der Bericht ist ein interner Nachweis, kein
  Γ-Objekt; Grants bleiben menschliche Akte (GO-Prinzip).

  **Epistemische Grenze:** Ein leeres Fenster ist kein Konfinement-Beweis.
  Die positive Kontrolle bleibt das Boot-Gate; der Bericht haelt diesen
  Vorbehalt selbst fest.

  **Redaktion:** Denial-Zeilen koennen Pfade nicht-oeffentlicher Inhalte
  enthalten. Jedes Target und jede Fehlermeldung laeuft vor dem Schreiben
  und vor dem Footer durch `redact/3` (`komki-denials-redact/1`).
  Systempfade bleiben verbatim, Home-/Instanz-/Scratch-Pfade werden
  maskiert, unbekannte absolute Pfade fallen auf `<redacted-path>`.

  Der `log show`-Aufruf laeuft als argv-Liste (keine Shell) im komki-BEAM,
  nicht unter dem pi-Profil und ohne sudo. Der Bericht wird atomar
  geschrieben: exklusive Temp-Datei im `0700`-Verzeichnis, sofort `0600`,
  `:file.sync`, Publikation per Hardlink. Bestehende Dateien werden nie
  ueberschrieben; parallele Writer bekommen einen Suffix.
  """

  alias KomkiCli.Config

  @log_binary "/usr/bin/log"

  @predicate ~S|(process == "kernel" OR sender == "Sandbox") AND eventMessage CONTAINS "Sandbox:" AND eventMessage CONTAINS "deny("|

  @timeout 15_000
  @report_schema "komki-denials/1"
  @max_footer_lines 5

  # Verbatim-Pfade: System- und Entwicklerorte, die fuer die
  # Grant-Discovery selbst relevant sind. Alles andere Absolute wird
  # redigiert.
  @verbatim_prefixes [
    "/System",
    "/usr",
    "/bin",
    "/sbin",
    "/Library",
    "/Applications",
    "/opt",
    "/private/etc",
    "/private/var/db",
    "/private/var/run",
    "/private/var/select",
    "/dev"
  ]

  # Unified-Log `--style compact` dieser macOS-Version: 3-stellige
  # Millisekunden und kein Offset (die UTC-Zone kommt vom `--timezone UTC`
  # des Aufrufs). Ältere Formen mit Offset und 6 Bruchstellen bleiben
  # parsebar. Der Header (`Timestamp ... Ty Process[PID:TID]`) ist keine
  # Denial-Zeile und wird uebersprungen.
  @logged_re ~S|\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:[+-]\d{4})?|

  @line_re Regex.compile!(
             "^(?<logged>" <>
               @logged_re <>
               ").*?Sandbox:\\s+(?<process>[^\\s(]+)\\((?<pid>\\d+)\\)\\s+deny\\((?<count>\\d+)\\)\\s+(?<operation>\\S+)\\s+(?<target>.+)$"
           )

  @duplicate_re Regex.compile!(
                  "^(?<logged>" <>
                    @logged_re <>
                    ").*?\\b(?<duplicate_count>\\d+) duplicate report for Sandbox:\\s+(?<process>[^\\s(]+)\\((?<pid>\\d+)\\)\\s+deny\\((?<count>\\d+)\\)\\s+(?<operation>\\S+)\\s+(?<target>.+)$"
                )

  @header_re ~r/^Timestamp\s+Ty\s+Process\[PID:TID\]/

  # Pfad-Run: optional ein Scheme/Host (`file://`, `https://host`), dann ein
  # absoluter oder Home-Pfad. Der Pfad darf Leerzeichen enthalten und endet
  # an Quotes, Klammern, Kommas/Semikolons oder Zeilenumbruechen. Das
  # fuehrende Zeichen bleibt erhalten (Quote, `=`, `(`, Whitespace ...).
  @path_re ~r"(?<lead>^|[\s\"'`(\[=,:;])(?<scheme>[a-zA-Z][a-zA-Z0-9+.\-]*://[^/\s]*)?(?<path>(?:/|~)[^\"'`()\[\]{}<>,;\n\r\t]*)"

  @type denial :: %{
          logged_at: String.t(),
          process: String.t(),
          pid: pos_integer(),
          deny_count: non_neg_integer(),
          operation: String.t(),
          target: String.t(),
          occurrences: pos_integer()
        }

  @type capture :: %{
          status: String.t(),
          log_binary: String.t(),
          argv: [String.t()],
          predicate: String.t(),
          error: String.t() | nil,
          matched: non_neg_integer(),
          parsed: non_neg_integer(),
          unparsed: non_neg_integer(),
          denials: [denial()],
          redacted_count: non_neg_integer()
        }

  @doc "Schema-Kennung der Berichtsdatei."
  @spec schema() :: String.t()
  def schema, do: @report_schema

  @doc "Absoluter Pfad des Denial-Berichtsverzeichnisses der Instanz."
  @spec dir(Config.t()) :: String.t()
  def dir(%Config{} = cfg), do: Path.join(cfg.base_dir, "denials")

  @doc """
  argv des Unified-Log-Aufrufs (absolute Binary, argv-Liste, keine Shell).

  `start`/`end` sind `DateTime`-Werte; beide werden als UTC-Wanduhrzeit mit
  explizitem `+0000` uebergeben. `--info`/`--debug` sind im MVP bewusst
  nicht gesetzt.
  """
  @spec show_args(%{start: DateTime.t(), end: DateTime.t()}) :: [String.t()]
  def show_args(%{start: %DateTime{}, end: %DateTime{}} = window),
    do: show_args(window, @log_binary)

  defp show_args(%{start: start, end: end_}, binary) do
    [
      binary,
      "show",
      "--style",
      "compact",
      "--timezone",
      "UTC",
      "--start",
      log_time(start, :floor),
      "--end",
      log_time(end_, :ceil),
      "--predicate",
      @predicate
    ]
  end

  @doc """
  `log show`-Ausgabe parsen und Duplikate gruppieren.

  Erwartet das kompakte Unified-Log-Format mit
  `Sandbox: <prozess>(<pid>) deny(<n>) <operation> <target>` — 3-stellige
  Millisekunden ohne Offset (Live-Format) wie auch aeltere Formen mit
  Offset. Der Format-Header `Timestamp ... Ty Process[PID:TID]` wird
  uebersprungen und zaehlt weder als Denial noch als unparsebar.

  `N duplicate report for Sandbox: ...`-Zeilen sind Wiederholungsbelege:
  Sie erzeugen keine eigene Denial-Zeile, sondern erhoehen `occurrences`
  der passenden Gruppe um `N`. Nicht parsebare Zeilen werden gezaehlt,
  nicht verworfen. Rueckgabe enthaelt die gruppierten Denials
  (Schluessel: Prozess, PID, deny-Zaehler, Operation, Target) mit
  `occurrences`; `logged_at` ist der erste Zeitstempel der Gruppe.
  `matched` zaehlt alle betrachteten Zeilen ohne Header, `parsed` alle
  erkannten Denial- und Duplicate-Zeilen.
  """
  @spec parse(String.t()) :: %{
          denials: [denial()],
          matched: non_neg_integer(),
          parsed: non_neg_integer(),
          unparsed: non_neg_integer()
        }
  def parse(output) when is_binary(output) do
    lines =
      output
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {entries, unparsed, matched} =
      Enum.reduce(lines, {[], 0, 0}, fn line, {acc, misses, considered} ->
        case parse_line(line) do
          {:ok, denial} -> {[denial | acc], misses, considered + 1}
          :error -> {acc, misses + 1, considered + 1}
          :skip -> {acc, misses, considered}
        end
      end)

    entries = Enum.reverse(entries)

    %{
      denials: group(entries),
      matched: matched,
      parsed: length(entries),
      unparsed: unparsed
    }
  end

  @doc """
  Capture des Lauffensters ueber `/usr/bin/log show`.

  Optionen:

    * `:base_dir` (Pflicht) — Instanz-Root fuer die Redaktion.
    * `:scratch` — Scratch-Pfad des Laufs (Redaktion).
    * `:runner` — injizierbar fuer Tests: `fn argv -> {output, exit_code} end`.
    * `:binary` — Log-Binary (Default `/usr/bin/log`; Tests ueberschreiben).
    * `:timeout` — Timeout in ms (Default 15_000).

  Statuswerte: `"ok"`, `"unavailable"`, `"error"`, `"timeout"`,
  `"unparseable"`. Nur bei `"ok"` wird ein Bericht geschrieben.
  """
  @spec capture(%{start: DateTime.t(), end: DateTime.t()}, keyword()) ::
          {:ok, capture()} | {:error, String.t()}
  def capture(window, opts \\ []) do
    base = Keyword.fetch!(opts, :base_dir)
    scratch = Keyword.get(opts, :scratch)
    binary = Keyword.get(opts, :binary, @log_binary)
    runner = Keyword.get(opts, :runner, &default_runner/1)
    timeout = Keyword.get(opts, :timeout, @timeout)
    argv = show_args(window, binary)

    if File.exists?(binary) do
      do_capture(runner, argv, timeout, binary, base, scratch)
    else
      {:ok,
       error_capture("unavailable", argv, binary, base, scratch, "log binary missing: " <> binary)}
    end
  rescue
    e ->
      base = Keyword.get(opts, :base_dir, "")
      scratch = Keyword.get(opts, :scratch)
      {:error, redact("denial capture failed: " <> Exception.message(e), base, scratch)}
  end

  defp do_capture(runner, argv, timeout, binary, base, scratch) do
    case run_log(runner, argv, timeout) do
      {:ok, {output, 0}} ->
        {:ok, ok_capture(output, argv, binary, base, scratch)}

      {:ok, {output, code}} ->
        {:ok,
         error_capture(
           "error",
           argv,
           binary,
           base,
           scratch,
           "log show exit " <> to_string(code) <> ": " <> output
         )}

      {:timeout} ->
        {:ok, error_capture("timeout", argv, binary, base, scratch, "log show timeout")}

      {:error, reason} ->
        {:ok, error_capture("error", argv, binary, base, scratch, reason)}
    end
  end

  defp ok_capture(output, argv, binary, base, scratch) do
    parsed = parse(output)
    {denials, redacted_count} = redact_denials(parsed.denials, base, scratch)

    cond do
      parsed.matched == 0 ->
        capture_map("ok", argv, binary,
          matched: 0,
          parsed: 0,
          unparsed: 0,
          denials: [],
          redacted_count: 0
        )

      parsed.parsed == 0 ->
        capture_map("unparseable", argv, binary,
          error: "output not parseable (" <> to_string(parsed.unparsed) <> " line(s))",
          matched: parsed.matched,
          parsed: 0,
          unparsed: parsed.unparsed,
          denials: [],
          redacted_count: 0
        )

      true ->
        capture_map("ok", argv, binary,
          matched: parsed.matched,
          parsed: parsed.parsed,
          unparsed: parsed.unparsed,
          denials: denials,
          redacted_count: redacted_count
        )
    end
  end

  defp error_capture(status, argv, binary, base, scratch, message) do
    # Redaktion VOR der Kuerzung: ein Schnitt mitten im Pfad wuerde sonst
    # einen Resttoken stehen lassen.
    {redacted, count} = redact_checked(message, base, scratch)

    capture_map(status, argv, binary,
      error: excerpt(redacted),
      denials: [],
      redacted_count: count
    )
  end

  defp capture_map(status, argv, binary, fields) do
    Map.merge(
      %{
        status: status,
        log_binary: binary,
        argv: argv,
        predicate: @predicate,
        error: nil,
        matched: 0,
        parsed: 0,
        unparsed: 0,
        denials: [],
        redacted_count: 0
      },
      Map.new(fields)
    )
  end

  # ------------------------------------------------------------------ Redaktion

  @doc """
  Redigiert ein Target oder eine Fehlermeldung (`komki-denials-redact/1`).

  Pfade werden auch dann erkannt, wenn sie in Anfuehrungszeichen, Klammern,
  `key=`-Formen oder `file://`-URLs eingebettet sind und Leerzeichen
  enthalten. Zuerst werden die nutzerspezifischen Praefixe
  Scratch/Base/asdf/nvm/Home (laengster zuerst) klassifiziert; Systemorte
  bleiben danach verbatim, jeder unbekannte absolute Pfad wird
  `<redacted-path>`. Nicht-Pfad-Targets (mach-Namen, sysctl-Namen,
  IOKit-Klassen, Netz-Endpunkte) bleiben unveraendert. Im Zweifel wird
  redigiert.
  """
  @spec redact(String.t(), String.t(), String.t() | nil) :: String.t()
  def redact(value, base, scratch) when is_binary(value) do
    Regex.replace(@path_re, value, fn _full, lead, scheme, path ->
      {core, tail} = split_trailing_whitespace(path)
      lead <> (scheme || "") <> classify_path(core, base, scratch) <> tail
    end)
  end

  defp classify_path(path, base, scratch) do
    case user_prefix(path, base, scratch) do
      nil -> if verbatim?(path), do: path, else: "<redacted-path>"
      placeholder -> placeholder
    end
  end

  # Nutzerspezifische Praefixe haben Vorrang vor den System-Verbatim-Orten:
  # ein Scratch unter /opt oder /Library bleibt ein Scratch.
  defp user_prefix(path, base, scratch) do
    home = System.user_home!()

    [
      {scratch, "<scratch>/<redacted>"},
      {base, "<base>/<redacted>"},
      {Path.join(home, ".asdf"), "<asdf>/<redacted>"},
      {"~/.asdf", "<asdf>/<redacted>"},
      {Path.join(home, ".nvm"), "<nvm>/<redacted>"},
      {"~/.nvm", "<nvm>/<redacted>"},
      {home, "<redacted-path>"}
    ]
    |> Enum.filter(fn {prefix, _placeholder} -> is_binary(prefix) and prefix != "" end)
    |> Enum.sort_by(fn {prefix, _placeholder} -> -byte_size(prefix) end)
    |> Enum.find_value(fn {prefix, placeholder} ->
      if under?(path, prefix), do: placeholder, else: nil
    end)
  end

  defp redact_denials(denials, base, scratch) do
    Enum.map_reduce(denials, 0, fn denial, count ->
      target = redact(denial.target, base, scratch)
      process = redact(denial.process, base, scratch)

      changed = if(target != denial.target, do: 1, else: 0)
      changed = changed + if(process != denial.process, do: 1, else: 0)

      {denial |> Map.put(:target, target) |> Map.put(:process, process), count + changed}
    end)
  end

  defp redact_checked(value, base, scratch) do
    redacted = redact(value, base, scratch)

    {redacted, if(redacted == value, do: 0, else: 1)}
  end

  defp split_trailing_whitespace(value) do
    core = String.trim_trailing(value)
    tail = binary_part(value, byte_size(core), byte_size(value) - byte_size(core))
    {core, tail}
  end

  defp verbatim?(value), do: Enum.any?(@verbatim_prefixes, &under?(value, &1))

  defp under?(value, prefix) when is_binary(prefix) and prefix != "" do
    prefix = String.trim_trailing(prefix, "/")
    value == prefix or String.starts_with?(value, prefix <> "/")
  end

  defp under?(_value, _prefix), do: false

  # --------------------------------------------------------------- Persistenz

  @doc """
  Schreibt den Bericht append-only und atomar.

  Der Dateiname kommt aus `created_at` und `run.scratch_hash`; existiert er
  bereits, wird ein numerischer Suffix angehaengt. Geschrieben wird in eine
  Temp-Datei im Zielverzeichnis (exklusiv erzeugt, sofort `0600`,
  `:file.sync`), danach per Hardlink publiziert: `:eexist` erzwingt den
  naechsten Suffix, ein vorhandenes Ziel wird nie ersetzt. Das Verzeichnis
  ist `0700`. Bei Fehlern bleibt kein Zielartefakt und keine Temp-Datei
  zurueck.
  """
  @spec write_report(Config.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def write_report(%Config{} = cfg, report) when is_map(report) do
    write_report(cfg, report, [])
  end

  @doc false
  @spec write_report(Config.t(), map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def write_report(%Config{} = cfg, report, opts) when is_map(report) and is_list(opts) do
    dir = dir(cfg)
    created_at = report["created_at"]
    scratch_hash = get_in(report, ["run", "scratch_hash"]) || ""

    result =
      with {:ok, datetime} <- parse_created_at(created_at),
           :ok <- ensure_dir(dir),
           {:ok, content} <- encode_report(report) do
        write_atomic(dir, file_base(datetime, scratch_hash), content, opts)
      end

    case result do
      {:ok, _path} = ok -> ok
      {:error, reason} -> {:error, redact(reason, cfg.base_dir, nil)}
    end
  rescue
    e ->
      reason = redact("cannot write denial report: " <> Exception.message(e), cfg.base_dir, nil)
      {:error, reason}
  end

  defp ensure_dir(dir) do
    with :ok <- mkdir_p(dir), do: chmod_dir(dir)
  end

  defp chmod_dir(dir) do
    case File.chmod(dir, 0o700) do
      :ok -> :ok
      {:error, reason} -> {:error, "cannot chmod denial directory: " <> posix(reason)}
    end
  end

  defp parse_created_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, "invalid created_at: " <> excerpt(value)}
    end
  end

  defp parse_created_at(_), do: {:error, "invalid created_at"}

  defp mkdir_p(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "cannot create " <> dir <> ": " <> posix(reason)}
    end
  end

  defp encode_report(report) do
    {:ok, JSON.encode!(report) <> "\n"}
  rescue
    e -> {:error, "cannot encode denial report: " <> Exception.message(e)}
  end

  defp write_atomic(dir, base, content, opts) do
    with {:ok, tmp, io} <- open_temp(dir, 5) do
      result =
        try do
          :ok = File.chmod(tmp, 0o600)
          run_temp_hook(opts, tmp)

          writer = Keyword.get(opts, :write_fun, &default_write/2)
          writer.(io, content)
        rescue
          e -> {:error, Exception.message(e)}
        catch
          kind, reason -> {:error, Kernel.inspect({kind, reason})}
        after
          File.close(io)
        end

      finish_atomic(result, tmp, dir, base)
    end
  end

  # Exklusiv erzeugen: ein vorhandener Pfad oder Symlink wird nie
  # wiederverwendet. Bei Namenskollision wird ein neuer Temp-Name versucht.
  defp open_temp(_dir, 0), do: {:error, "cannot create temp report: too many collisions"}

  defp open_temp(dir, attempts) do
    tmp = Path.join(dir, ".tmp-" <> unique_suffix())

    case File.open(tmp, [:write, :binary, :exclusive]) do
      {:ok, io} -> {:ok, tmp, io}
      {:error, :eexist} -> open_temp(dir, attempts - 1)
      {:error, reason} -> {:error, "cannot open temp report: " <> posix(reason)}
    end
  end

  defp run_temp_hook(opts, tmp) do
    case Keyword.get(opts, :on_temp_open) do
      nil -> :ok
      fun when is_function(fun, 1) -> fun.(tmp)
    end
  end

  defp default_write(io, content) do
    :ok = IO.binwrite(io, content)
    :file.sync(io)
  end

  defp finish_atomic(:ok, tmp, dir, base) do
    publish(tmp, dir, base, 0)
  end

  defp finish_atomic({:error, _} = error, tmp, _dir, _base) do
    File.rm(tmp)
    error
  end

  # Publikation per Hardlink: atomar und ohne Ueberschreiben. Ein
  # vorhandenes Ziel liefert `:eexist`; dann folgt der naechste Suffix.
  # Zwei parallele Writer erzeugen so garantiert zwei Berichte.
  defp publish(tmp, dir, base, n) do
    candidate = if n == 0, do: base, else: base <> "-" <> Integer.to_string(n)
    path = Path.join(dir, candidate <> ".json")

    case File.ln(tmp, path) do
      :ok ->
        File.rm(tmp)
        {:ok, path}

      {:error, :eexist} ->
        publish(tmp, dir, base, n + 1)

      {:error, reason} ->
        File.rm(tmp)
        {:error, "cannot publish report: " <> posix(reason)}
    end
  end

  defp file_base(datetime, scratch_hash) do
    stamp =
      datetime
      |> utc_naive()
      |> Calendar.strftime("%Y%m%dT%H%M%S.%fZ")

    stamp <> "-" <> binary_part(scratch_hash, 0, min(12, byte_size(scratch_hash)))
  end

  # ------------------------------------------------------------------ Footer

  @doc """
  Menschlicher Footer fuer stderr.

  Bei Erfolg: `denials: N captured (M unique) — report: <pfad>` plus
  maximal fuenf gruppierte `operation target ×n`-Zeilen. Ohne Denials:
  `denials: none in run window`. Bei Capture-/Persistenzfehlern:
  `denials: capture FAILED (<reason>); no report`.
  """
  @spec footer(map()) :: String.t()
  def footer(%{status: "ok", denials: [], report_path: _path}) do
    "denials: none in run window"
  end

  def footer(%{status: "ok", denials: denials, report_path: path}) do
    total = Enum.sum(Enum.map(denials, & &1.occurrences))

    head =
      "denials: " <>
        to_string(total) <>
        " captured (" <> to_string(length(denials)) <> " unique) — report: " <> to_string(path)

    shown =
      denials
      |> Enum.sort_by(fn denial -> {-denial.occurrences, denial.operation, denial.target} end)
      |> Enum.take(@max_footer_lines)

    lines =
      Enum.map(shown, fn denial ->
        "  " <> denial.operation <> " " <> denial.target <> " ×" <> to_string(denial.occurrences)
      end)

    remaining = length(denials) - length(shown)
    more = if remaining > 0, do: ["  … weitere " <> to_string(remaining)], else: []

    Enum.join([head | lines] ++ more, "\n")
  end

  def footer(%{error: reason}) when is_binary(reason) do
    # Sicherheitsnetz: selbst ein unredigierter Summary-Fehler verliert hier
    # Home-/absolute Pfade, auch wenn Steps bereits zentral redigiert.
    "denials: capture FAILED (" <> redact(reason, "", nil) <> "); no report"
  end

  def footer(_summary), do: "denials: capture FAILED (unknown error); no report"

  # ------------------------------------------------------------------ Helfer

  defp default_runner([program | args]) do
    System.cmd(program, args, stderr_to_stdout: true)
  end

  defp run_log(runner, argv, timeout) do
    task = Task.async(fn -> safe_runner(runner, argv) end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        runner_result(result)

      {:exit, reason} ->
        {:error, "log runner crashed: " <> Kernel.inspect(reason)}

      nil ->
        # Drain-/Haenge-Schutz: der `log show`-Kindprozess wird beim
        # Timeout brutal beendet, damit kein Runner den BEAM blockiert.
        case Task.shutdown(task, :brutal_kill) do
          {:ok, result} -> runner_result(result)
          _ -> {:timeout}
        end
    end
  end

  defp safe_runner(runner, argv) do
    {:ok, runner.(argv)}
  rescue
    e -> {:error, "log runner crashed: " <> Exception.message(e)}
  catch
    kind, reason -> {:error, "log runner crashed: " <> Kernel.inspect({kind, reason})}
  end

  defp runner_result({:ok, {output, code}}) when is_binary(output) and is_integer(code),
    do: {:ok, {output, code}}

  defp runner_result({:ok, other}),
    do: {:error, "unexpected log runner result: " <> Kernel.inspect(other)}

  defp runner_result({:error, reason}), do: {:error, reason}

  defp parse_line(line) do
    cond do
      Regex.match?(@header_re, line) -> :skip
      duplicate = duplicate_entry(line) -> duplicate
      denial = denial_entry(line) -> denial
      true -> :error
    end
  end

  defp duplicate_entry(line) do
    case Regex.named_captures(@duplicate_re, line) do
      nil -> nil
      match -> {:ok, build_denial(match, String.to_integer(match["duplicate_count"]))}
    end
  end

  defp denial_entry(line) do
    case Regex.named_captures(@line_re, line) do
      nil -> nil
      match -> {:ok, build_denial(match, 1)}
    end
  end

  defp build_denial(match, occurrences) do
    %{
      logged_at: utc_iso(match["logged"]),
      process: match["process"],
      pid: String.to_integer(match["pid"]),
      deny_count: String.to_integer(match["count"]),
      operation: match["operation"],
      target: String.trim_trailing(match["target"]),
      occurrences: occurrences
    }
  end

  defp group(entries) do
    {by_key, order} =
      Enum.reduce(entries, {%{}, []}, fn denial, {map, keys} ->
        key = {denial.process, denial.pid, denial.deny_count, denial.operation, denial.target}

        case Map.fetch(map, key) do
          {:ok, existing} ->
            updated = %{existing | occurrences: existing.occurrences + denial.occurrences}
            {Map.put(map, key, updated), keys}

          :error ->
            {Map.put(map, key, denial), [key | keys]}
        end
      end)

    order
    |> Enum.reverse()
    |> Enum.map(&Map.fetch!(by_key, &1))
  end

  defp utc_iso(raw) do
    case parse_log_time(raw) do
      {:ok, datetime} -> DateTime.to_iso8601(datetime)
      :error -> raw
    end
  end

  defp parse_log_time(raw) do
    regex =
      ~r/^(?<date>\d{4}-\d{2}-\d{2}) (?<time>\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?)(?<offset>[+-]\d{4})?$/

    with %{"date" => date, "time" => time, "offset" => offset} <- Regex.named_captures(regex, raw),
         {:ok, naive} <- NaiveDateTime.from_iso8601(date <> "T" <> time) do
      utc = NaiveDateTime.add(naive, -offset_seconds(offset), :second)
      {:ok, DateTime.from_naive!(utc, "Etc/UTC")}
    else
      _ -> :error
    end
  end

  # Ohne Offset ist der Zeitstempel bereits UTC (`--timezone UTC`);
  # `Named-Captures` liefert fuer die optionale Gruppe `""`.
  defp offset_seconds(offset) when offset in [nil, ""], do: 0

  defp offset_seconds(<<sign, hours::binary-size(2), minutes::binary-size(2)>>) do
    seconds = String.to_integer(hours) * 3600 + String.to_integer(minutes) * 60
    if sign == ?-, do: -seconds, else: seconds
  end

  # `/usr/bin/log show` akzeptiert auf dieser macOS-Version nur
  # sekundengenaue Zeitstempel im Format `%Y-%m-%d %H:%M:%S%z`
  # (Live-Befund: Bruchteile fuehren zu Exit 64). Start wird abgerundet,
  # Ende aufgerundet — das Fenster darf nie schrumpfen.
  defp log_time(%DateTime{} = datetime, rounding) do
    naive =
      datetime
      |> utc_naive()
      |> round_to_second(rounding)

    Calendar.strftime(naive, "%Y-%m-%d %H:%M:%S") <> "+0000"
  end

  defp round_to_second(naive, :floor), do: NaiveDateTime.truncate(naive, :second)

  defp round_to_second(%NaiveDateTime{microsecond: {0, _}} = naive, :ceil),
    do: NaiveDateTime.truncate(naive, :second)

  defp round_to_second(naive, :ceil) do
    naive
    |> NaiveDateTime.add(1, :second)
    |> NaiveDateTime.truncate(:second)
  end

  # Wanduhrzeit in UTC; die Datetime-Zone selbst wird nicht gebraucht.
  defp utc_naive(%DateTime{} = datetime) do
    offset = datetime.utc_offset + datetime.std_offset
    NaiveDateTime.add(DateTime.to_naive(datetime), -offset, :second)
  end

  defp excerpt(text) do
    text
    |> String.trim_trailing()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 500)
  end

  defp posix(reason), do: List.to_string(:file.format_error(reason))

  defp unique_suffix do
    Integer.to_string(System.unique_integer([:positive])) <>
      "-" <> Integer.to_string(System.system_time(:microsecond))
  end
end
