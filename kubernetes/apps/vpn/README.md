# vpn

A VPN egress gateway and its DNS, so selected workloads (e.g. the
[`downloads`](../downloads/README.md) apps) can route their traffic through a VPN. The
namespace uses an internal `192.168.24.0/24` overlay with fixed pod IPs.

| App | Description | Manifest |
| --- | --- | --- |
| [gateway](https://github.com/qdm12/gluetun) | Gluetun VPN client gateway pod; other workloads egress through it. | [ks.yaml](./gateway/ks.yaml) |
| [dns](https://dnsdist.org/) | dnsdist resolver for the VPN namespace. | [ks.yaml](./dns/ks.yaml) |

See the design doc under [`docs/plans`](../../../docs/plans) for the full VPN-gateway
architecture.
