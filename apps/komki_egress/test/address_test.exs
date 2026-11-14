defmodule KomkiEgress.AddressTest do
  use ExUnit.Case, async: true

  alias KomkiEgress.Address

  defp ip(text) do
    {:ok, ip} = :inet.parse_address(String.to_charlist(text))
    ip
  end

  @blocked_v4 [
    "0.0.0.0",
    "0.255.255.255",
    "10.0.0.1",
    "10.255.255.255",
    "100.64.0.1",
    "100.127.255.255",
    "127.0.0.1",
    "127.255.255.254",
    "169.254.0.1",
    "169.254.169.254",
    "172.16.0.1",
    "172.31.255.255",
    "192.0.0.1",
    "192.0.2.1",
    "192.168.0.1",
    "192.168.255.255",
    "198.18.0.1",
    "198.19.255.255",
    "198.51.100.1",
    "203.0.113.1",
    "224.0.0.1",
    "239.255.255.255",
    "240.0.0.1",
    "255.255.255.255"
  ]

  @public_v4 [
    "1.1.1.1",
    "8.8.8.8",
    "9.255.255.255",
    "11.0.0.0",
    "100.63.255.255",
    "100.128.0.0",
    "126.255.255.255",
    "128.0.0.0",
    "169.253.255.255",
    "169.255.0.0",
    "172.15.255.255",
    "172.32.0.0",
    "192.167.255.255",
    "192.169.0.0",
    "198.17.255.255",
    "198.20.0.0",
    "223.255.255.255"
  ]

  @blocked_v6 [
    "::",
    "::1",
    "::127.0.0.1",
    "::ffff:127.0.0.1",
    "::ffff:10.0.0.1",
    "::ffff:8.8.8.8",
    "64:ff9b::a00:1",
    "100::1",
    "2001:db8::1",
    "fc00::1",
    "fd12:3456::1",
    "fe80::1",
    "febf:ffff::1",
    "fec0::1",
    "ff02::1"
  ]

  @public_v6 [
    "2606:4700:4700::1111",
    "2001:4860:4860::8888",
    "2a00:1450:4001::1",
    "fbff:ffff::1",
    "::ffff:0:0:1"
  ]

  test "blockierte IPv4-Adressen sind nicht öffentlich" do
    for text <- @blocked_v4, do: refute(Address.public?(ip(text)), text)
  end

  test "öffentliche IPv4-Adressen, auch an den Netzgrenzen" do
    for text <- @public_v4, do: assert(Address.public?(ip(text)), text)
  end

  test "blockierte IPv6-Adressen inkl. eingebetteter IPv4" do
    for text <- @blocked_v6, do: refute(Address.public?(ip(text)), text)
  end

  test "öffentliche IPv6-Adressen" do
    for text <- @public_v6, do: assert(Address.public?(ip(text)), text)
  end

  test "alles andere ist nicht öffentlich" do
    refute Address.public?(nil)
    refute Address.public?("8.8.8.8")
    refute Address.public?({8, 8, 8})
    refute Address.public?({8, 8, 8, 256})
    refute Address.public?({8, 8, 8, -1})
    refute Address.public?({0x2606, 0, 0, 0, 0, 0, 0, 0x10000})
  end
end
