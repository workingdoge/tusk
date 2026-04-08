{ builtins ? builtins, pluginPath }:
if !(builtins ? wasm) then
  throw "Determinate Nix with `--extra-experimental-features wasm-builtin` is required"
else
  let
    resolver = builtins.wasm {
      path = pluginPath;
      function = "resolve";
    };
  in
  {
    resolve =
      { rid, seed, branch }:
      resolver {
        inherit rid seed branch;
        resolveRev =
          { url, ref }:
          (builtins.fetchTree {
            type = "git";
            inherit url ref;
          }).rev;
      };

    resolveWithRev =
      { rid, seed, branch, rev }:
      resolver {
        inherit rid seed branch rev;
      };
  }
