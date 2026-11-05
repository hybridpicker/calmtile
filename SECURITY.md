# Security

calmtile holds Accessibility access and runs a key tap, so reports about it deserve care.

## Reporting a vulnerability

Please report privately through GitHub: open the **Security** tab of this repository and choose **Report a
vulnerability**. Do not open a public issue for it. This is a one-person project; expect a first answer within
a few days.

## What is in scope

Anything that makes calmtile read, store or send more than described under *Privacy* in the
[README](README.md): keys, window titles, files, network traffic, or a way for another process to make calmtile
act on its behalf (for example through `~/.config/calmtile/command`, which is only read while `CALMTILE_DEBUG`
is set).

## Supported versions

Only the latest commit on `main` and the latest release.
