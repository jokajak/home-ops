# default namespace applications

This directory contains all of the applications deployed to the `default`
namespace.

## authentik

[authentik](https://goauthentik.io/) is used to provide authorization and SSO capabilities for services. The intention
is to use external credentials like google accounts or github accounts for authentication and authentik local or
application local groups for authorization.

* [authentik.yaml](./authentik/ks.yaml)

The authentik configuration is stored as IaC using [terraform](../../../terraform/authentik/README.md)

## frigate

![image of frigate](https://i.imgur.com/hv7bh6m.png)

Installs [frigate](https://github.com/blakeblackshear/frigate/): Realtime object detection on RTSP cameras with the Google Coral

* [frigate](frigate/app/helmrelease.yaml)

## home-assistant

[home-assistant](https://www.home-assistant.io/) provides home automation services.

* [homeassistant.yaml](./home-assistant/ks.yaml)

## immich

[immich](https://github.com/immich-app/immich) is used to backup photos.

* [immich.yaml](./immich/ks.yaml)

## unifi

[ubiquiti unifi controller](https://github.com/jacobalberty/unifi-docker) for
wireless access points and home networking

* [unifi.yaml](./unifi/ks.yaml)

## zwave-js-ui

[zwave-js-ui](https://zwave-js.github.io/zwave-js-ui/#/) is used to manage the zwave devices. zwave is a wireless
protocol used for IoT.

* [zwavejs.yaml](./zwave-js-ui/ks.yaml)
