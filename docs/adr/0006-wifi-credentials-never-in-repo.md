# Wifi credentials never enter the repo

The repo is version-controlled and shared across machines, so wifi is
configured as a NetworkManager persistent profile created manually per
machine, entirely outside the repo — credentials must never enter git
history. netplan itself is still nix-owned (`replaceExisting`); only the
credentialed NetworkManager profile is out-of-repo.
