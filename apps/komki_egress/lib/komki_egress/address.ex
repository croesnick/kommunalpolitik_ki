defmodule KomkiEgress.Address do
  @moduledoc """
  Prüft aufgelöste Zieladressen (DNS-Rebinding-Schutz, CONTRACT §9).

  `public?/1` ist nur für Adressen im öffentlichen Internet wahr. Abgelehnt
  werden private Netze, Loopback, Link-Local (inkl. Metadaten-Adresse
  169.254.169.254), CGNAT, Multicast, reservierte und Dokumentationsnetze
  sowie IPv6-Formen, die eine IPv4-Adresse einbetten (IPv4-mapped,
  IPv4-compatible, NAT64). Alles, was kein IPv4- oder IPv6-Tupel ist, gilt
  ebenfalls als nicht öffentlich.
  """

  import Bitwise

  @v4_blocked [
    # "dieses Netz", u. a. 0.0.0.0
    {{0, 0, 0, 0}, 8},
    # privat (RFC 1918)
    {{10, 0, 0, 0}, 8},
    # CGNAT (RFC 6598)
    {{100, 64, 0, 0}, 10},
    # Loopback
    {{127, 0, 0, 0}, 8},
    # Link-Local inkl. Metadaten-Adresse 169.254.169.254
    {{169, 254, 0, 0}, 16},
    # privat (RFC 1918)
    {{172, 16, 0, 0}, 12},
    # IETF-Protokollzuweisungen
    {{192, 0, 0, 0}, 24},
    # Dokumentation TEST-NET-1
    {{192, 0, 2, 0}, 24},
    # privat (RFC 1918)
    {{192, 168, 0, 0}, 16},
    # Benchmarking
    {{198, 18, 0, 0}, 15},
    # Dokumentation TEST-NET-2
    {{198, 51, 100, 0}, 24},
    # Dokumentation TEST-NET-3
    {{203, 0, 113, 0}, 24},
    # Multicast
    {{224, 0, 0, 0}, 4},
    # reserviert inkl. Broadcast 255.255.255.255
    {{240, 0, 0, 0}, 4}
  ]

  @v6_blocked [
    # unspezifiziert ::
    {{0, 0, 0, 0, 0, 0, 0, 0}, 128},
    # Loopback ::1
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
    # IPv4-compatible ::a.b.c.d (veraltet, bettet IPv4 ein)
    {{0, 0, 0, 0, 0, 0, 0, 0}, 96},
    # IPv4-mapped ::ffff:a.b.c.d
    {{0, 0, 0, 0, 0, 0xFFFF, 0, 0}, 96},
    # NAT64 64:ff9b::/96 (bettet IPv4 ein)
    {{0x64, 0xFF9B, 0, 0, 0, 0, 0, 0}, 96},
    # Discard-Präfix
    {{0x100, 0, 0, 0, 0, 0, 0, 0}, 64},
    # Dokumentation
    {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32},
    # Unique Local fc00::/7
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    # Link-Local fe80::/10
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    # Site-Local fec0::/10 (veraltet)
    {{0xFEC0, 0, 0, 0, 0, 0, 0, 0}, 10},
    # Multicast
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @doc "Wahr genau dann, wenn `ip` eine öffentlich routbare Adresse ist."
  @spec public?(term()) :: boolean()
  def public?({_, _, _, _} = ip), do: valid?(ip, 255) and not blocked?(ip, @v4_blocked, 8, 32)

  def public?({_, _, _, _, _, _, _, _} = ip),
    do: valid?(ip, 0xFFFF) and not blocked?(ip, @v6_blocked, 16, 128)

  def public?(_), do: false

  defp valid?(ip, max) do
    ip
    |> Tuple.to_list()
    |> Enum.all?(&(is_integer(&1) and &1 >= 0 and &1 <= max))
  end

  defp blocked?(ip, ranges, bits, total) do
    value = to_int(ip, bits)

    Enum.any?(ranges, fn {base, prefix} ->
      shift = total - prefix
      value >>> shift == to_int(base, bits) >>> shift
    end)
  end

  defp to_int(ip, bits) do
    ip
    |> Tuple.to_list()
    |> Enum.reduce(0, fn part, acc -> acc <<< bits ||| part end)
  end
end
