lib:
with lib; rec {
  getGVK = object: let
    splitApiVersion = splitString "/" object.apiVersion;
  in {
    inherit (object) kind;

    group =
      if length splitApiVersion < 2
      then "core"
      else elemAt splitApiVersion 0;
    version =
      if length splitApiVersion < 2
      then elemAt splitApiVersion 0
      else elemAt splitApiVersion 1;
  };
  # Recursively flatten *List objects
  flattenListObjects = builtins.concatMap (object:
    if builtins.match "^.*List$" object.kind != null
    then flattenListObjects object.items
    else [object]
  );
}
