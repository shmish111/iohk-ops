{ name, config, resources, ... }:

with import ./../lib.nix;
{
  config = {

    global = {
      allocateElasticIP = true;
      enableEkgWeb      = true;
      dnsDomainname     = "awstest.iohkdev.io";
    };

    services = {
      # temporary space until https://github.com/NixOS/nixpkgs/pull/30141 is in effect
      dd-agent.tags              = ["env:staging" "depl:${config.deployment.name}"];

      # DEVOPS-64: disable log bursting
      journald.rateLimitBurst    = 0;
    };

  };
}
