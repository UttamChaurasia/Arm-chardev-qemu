# Running on Windows with WSL2

Everything here needs a Linux host. On Windows that means WSL2 with Ubuntu.
Confirmed working: **Ubuntu 26.04 under WSL2** (quick start). The build-from-source
path was tested on Ubuntu 24.04.

## 1. Pick the right distro

In **cmd** (Windows), run `wsl -l -v`. You need an Ubuntu distro with `VERSION 2`.

If a distro called `docker-desktop` has the `*` next to it, that is the *default*,
and it is not usable: it is Docker's internal system and has no `apt`. Either:

```
wsl --set-default Ubuntu      # make Ubuntu the default
wsl -d Ubuntu                 # or open it explicitly each time
```

## 2. Know which prompt you are in

`C:\Users\you>` is Windows cmd. `you@PC:~$` is Linux. All project commands
(`sudo apt ...`, `./scripts/...`) go in the Linux prompt. Running a Linux command
in cmd gives "is not recognized".

## 3. Work in the Linux filesystem

Copy the zip into your Linux home and unzip it there. Do not work under `/mnt/c/...`:
it is slow and does not keep Unix permissions.

```bash
cd ~
cp /mnt/c/Users/<you>/Downloads/arm-chardev-qemu.zip ~/
unzip -q arm-chardev-qemu.zip && cd arm-chardev-qemu
```

Unzip inside WSL, not with Windows Explorer. If scripts fail with
`bad interpreter`, the line endings became CRLF; fix with
`sed -i 's/\r$//' scripts/*.sh rootfs/*`. (`.gitattributes` prevents this for git clones.)

## 4. Install and check

```bash
sudo apt update
sudo apt install -y qemu-system-arm gdb-multiarch unzip
./scripts/check-env.sh          # reports anything still missing
./scripts/run-tests.sh          # runs every mode and checks the results
```

## Notes

- The QEMU console has no window: quit with **Ctrl-A then X**, or `poweroff -f` in the guest.
- Emulation is in software, so the first boot takes a little while. No KVM is needed.
- A clean pass prints `== ALL PASSED (0 failures) ==` and `stress OK (20 cycles)`.
