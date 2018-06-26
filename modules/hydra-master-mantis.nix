{ resources, config, pkgs, lib, nodes, ... }:

with lib;

let
in {

  nix = {
    buildMachines = [
      { hostName = "localhost";
        system = "x86_64-linux,builtin";
        maxJobs = 8;
        supportedFeatures = ["kvm" "nixos-test"];
      }
    ];
    gc.automatic = true;
    useSandbox = mkForce false;
  };

  services.fail2ban.enable = true;
  virtualisation.docker.enable = true;

  services.hydra = {
    hydraURL = "https://hydra-mantis.iohk.io";
    # max output is 4GB because of amis
    # auth token needs `repo:status`
    extraConfig = ''
      max_output_size = 4294967296
      store-uri = file:///nix/store?secret-key=/etc/nix/hydra.iohk.io-1/secret
      binary_cache_secret_key_file = /etc/nix/hydra.iohk.io-1/secret
      <github_authorization>
        input-output-hk = ${builtins.readFile ../static/github_token}
      </github_authorization>
    '';
  };

  security.acme.certs = {
    "hydra-mantis.iohk.io" = {
      email = "info@iohk.io";
      user = "nginx";
      group = "nginx";
      webroot = config.security.acme.directory + "/acme-challenge";
      postRun = "systemctl reload nginx.service";
    };
  };

  services.nginx = {
    httpConfig = ''
      server_names_hash_bucket_size 64;

      keepalive_timeout   70;
      gzip            on;
      gzip_min_length 1000;
      gzip_proxied    expired no-cache no-store private auth;
      gzip_types      text/plain application/xml application/javascript application/x-javascript text/javascript text/xml text/css;

      server {
        server_name _;
        listen 80;
        listen [::]:80;
        location /.well-known/acme-challenge {
          root ${config.security.acme.certs."hydra-mantis.iohk.io".webroot};
        }
        location / {
          return 301 https://$host$request_uri;
        }
      }

      server {
        listen 443 ssl spdy;
        server_name hydra-mantis.iohk.io;

        ssl_certificate /var/lib/acme/hydra.iohk.io/fullchain.pem;
        ssl_certificate_key /var/lib/acme/hydra.iohk.io/key.pem;

        location / {
          proxy_pass http://127.0.0.1:8080;
          proxy_set_header Host $http_host;
          proxy_set_header REMOTE_ADDR $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
        }
      }
    '';
  };
}
