# Here, I fixed it for you, pCloud!

A tiny watchdog that babysits pCloud Drive on macOS so that when it locks up, it
takes pCloud down with it instead of your whole Mac.

<!-- Drop your hero image here once you have it: -->
<!-- ![hero](docs/hero.png) -->

## What this fixes

You are working. Maybe saving a file, maybe just clicking around in Finder. Then
everything stops. The cursor turns into the spinning beachball. Finder is dead,
your terminal is dead, your editor won't save, and the only thing that brings the
machine back is a reboot or killing pCloud by hand. An hour later it happens
again.

If that sounds familiar, this repo is for you. It does not stop pCloud from
freezing. It can't; the bug is inside pCloud. What it does is notice the freeze
within a few seconds and kill pCloud before the freeze spreads to the rest of the
system. A multi-minute lockup becomes a ten-second blip.

## Why this happens (and why it isn't your fault)

pCloud Drive doesn't sync files into a normal folder. It mounts a virtual drive
using its own in-kernel FUSE kernel extension, `com.pcloud.pcloudfs`. That part
matters more than it sounds.

When code lives in the kernel and it stalls, it doesn't just fail politely. Any
process that so much as looks at the mount, a `stat()`, a directory listing,
Spotlight poking around, gets parked in an uninterruptible kernel wait. You can't
Ctrl-C it. You can't Force Quit it. It sits there holding locks until the thing
it's waiting on comes back. When pCloud's daemon wedges (a slow network read, a
stuck lock, whatever), that "thing" never comes back on its own, and one by one
your apps walk into the same trap. Finder touches the mount and freezes. Your
shell freezes. The system feels dead because, for practical purposes, it is.

Killing pCloud releases those kernel locks instantly, and everything springs back
to life. That single observation is the whole basis for this fix.

And it's the architecture, not some tweak in the next build, that's the problem.
Apple has spent years pushing developers *away* from kernel extensions precisely because a bad one can take down the whole
OS, and there are now kext-free ways to do FUSE on macOS (see
[FUSE-T](https://github.com/macos-fuse-t/fuse-t), which runs over an NFS server
instead of a kernel extension). pCloud still ships the old kext.

## "Years, you say?"

Yes. This is not a new bug or a one-off on some weird setup. Go read:

- pCloud's own [Common Issues with pCloud Drive on macOS](https://blog.pcloud.com/common-issues-with-pcloud-drive-on-macos/)
- The [macOS release notes](https://www.pcloud.com/release-notes/mac-os.html),
  where "fixed issues that could cause crashes and freezes" shows up again, and
  again, and again across releases
- Apple's own support forums, where people on Monterey, Ventura, and Sonoma, on
  both Intel and Apple Silicon, describe the same beachball and the same
  reboot-only recovery: for example
  [this thread](https://discussions.apple.com/thread/255266704)

Every macOS release the patch notes promise stability is fixed. Every macOS
release people are still rebooting to get their Macs back. At some point a
"recurring stability fix" stops being a fix and starts being a confession.

So, pCloud: here's a 100-line shell script that papers over your kernel bug. It
took an afternoon. You're welcome. We'd much rather delete this repo because you
moved off the kext. The offer stands.

## How it works

A LaunchAgent runs the watchdog every 30 seconds. Each run:

1. Pokes the mount with a `stat()` on a path that can't exist, under a hard
   12-second timeout. A healthy daemon answers instantly. A wedged one doesn't
   answer at all.
2. If the mount is hung, it grabs a short stack sample of the stuck daemon first
   and saves it, so you can actually see where pCloud got stuck instead of just
   guessing.
3. Then it `kill -9`s pCloud (daemon plus the Finder extension), which releases
   the kernel locks and unfreezes the system, and relaunches the app.

The probe and the sample both run in the background and are watched on a timer,
because a probe that hits the hung mount will itself get stuck in the kernel. The
watchdog never waits on it directly, or it would hang right alongside everything
else. There's also a lock file so two runs can't trip over each other during a
recovery.

If you quit pCloud yourself, the watchdog notices it isn't running and does
nothing.

## Install

```sh
git clone https://github.com/watchdealer-pavel/pcloud-macos-freeze-fix.git
cd pcloud-macos-freeze-fix
./install.sh
```

That copies the script into `~/Library/Application Support/pcloud-watchdog/`,
writes a LaunchAgent to `~/Library/LaunchAgents/com.pcloud-watchdog.plist`, and
loads it. It starts watching right away and on every login.

Requirements: macOS, pCloud Drive in `/Applications`, and bash (already on your
Mac). Everything the script uses (`stat`, `sample`, `pkill`, `launchctl`,
`open`) ships with macOS.

If your drive isn't at the default `~/pCloud Drive`, open `watchdog.sh`, change
the `MOUNT` line at the top, and run `./install.sh` again.

## Uninstall

```sh
./uninstall.sh            # removes the agent and script, keeps logs
./uninstall.sh --purge-logs   # also deletes the logs
```

## Seeing what it's doing

Everything lands in `~/Library/Logs/pcloud-watchdog/`:

- `watchdog.log` is the running history: when a hang was caught, when pCloud was
  killed and relaunched.
- `hang-YYYYMMDD-HHMMSS.sample.txt` is a stack sample of the daemon taken at the
  moment it was stuck. Open one and look at where the threads are parked: a
  network read points at pCloud's servers or your connection, a lock points at
  pCloud's own code. It won't fix anything, but it's good ammunition if you want
  to file a bug pCloud can't wave away.

## A few honest caveats

- This is unofficial and has nothing to do with pCloud the company.
- `kill -9` is a sledgehammer, on purpose. A wedged kernel mount doesn't respond
  to a polite shutdown, so there's no graceful option to offer. In-flight uploads
  could be interrupted; pCloud picks them back up on relaunch, but know that's
  the trade.
- It treats the symptom, not the disease. The real fix has to come from pCloud.

## License

WTFPL. Do whatever you want with it. See [LICENSE](LICENSE).
