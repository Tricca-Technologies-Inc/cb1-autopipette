# Boot splash

Current CB1 images (Armbian 26.x, kernel >= 6.x) have NO kernel bootsplash
patchset (verified: no CONFIG_BOOTSPLASH on 6.18.33) — the blob mechanism
(`bootsplash.armbian` / bootsplash-packer / BTT's armbian-bootlogo) cannot
render on them. Plymouth with a two-step theme is the working mechanism,
verified on the CB1 panel. (Legacy pre-v3.0.0 BTT images are the reverse:
blob works, plymouth doesn't. Nothing here supports them.)

## How it works here
`install-tricca-theme.sh` (called by bootstrap step 6) forks the packaged
armbian theme into an owned `tricca` theme:
- your `watermark.png` (from `config/tricca-logo.png`), throbber BELOW it
- positions are `LOGO_V` / `THROB_V` at the top of the script (0-1 screen fractions)
- optional `LOGO_WIDTH` resizes the logo via imagemagick; or pre-size the PNG
  in any editor (panel res: `cat /sys/class/graphics/fb0/virtual_size`;
  ~40-50% of panel width is a good start)
- `plymouth-set-default-theme -R tricca` rebuilds the initramfs

`bootlogo=true` in /boot/armbianEnv.txt makes Armbian's boot.cmd pass
`splash plymouth.ignore-serial-consoles`; `console=serial` keeps boot text
off the panel. The kiosk unit quits plymouth with `--retain-splash` and X
starts with `-background none`, so the logo holds until Chromium paints.

## Tuning loop (no reboots)
Edit LOGO_V/THROB_V/LOGO_WIDTH, then:

    sudo ./install-tricca-theme.sh ../config/tricca-logo.png
    splash-preview          # shell helper: stops kiosk, shows splash 5s, restores
