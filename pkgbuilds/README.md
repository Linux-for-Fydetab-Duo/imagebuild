# PKGBUILDs

This repository contains PKGBUILDs for that are nessesary to run ArchLinuxARM on the Fydetab Duo.


## Usage

To use these PKGBUILDs, you need to have the `base-devel` group installed. You can install it with the following command:

```sh
sudo pacman -S base-devel
```

Then, to build a package, you can use the `makepkg` command. For example, to build the `linux-fydetab` package, you can run the following command:

```sh
cd linux-fydetab
makepkg -si
```
