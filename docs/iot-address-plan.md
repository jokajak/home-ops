# IoT address plan

Address allocation convention for the IoT segment. `A.B.C` stands in for the real prefix, which
lives in `cluster-secrets` (SOPS) as `${IOT_CIDR}` and is deliberately not committed here — see
the network-details policy in [`CLAUDE.md`](../CLAUDE.md).

| Range | Devices |
| --- | --- |
| `A.B.C.10-14` | Televisions |
| `A.B.C.15-19` | Rokus |
| `A.B.C.20-29` | Printers |
| `A.B.C.30-39` | Game systems |
| `A.B.C.40-49` | Cameras |
| `A.B.C.50-99` | Outlets / switches |
| `A.B.C.100-149` | Lights |
| `A.B.C.150-199` | Sensors |
| `A.B.C.200-249` | Misc |
