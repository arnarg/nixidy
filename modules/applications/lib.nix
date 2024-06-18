lib:
with lib; {
  getGVK = object: let
    splitApiVersion = splitString "/" object.apiVersion;
  in {
    group =
      if length splitApiVersion < 2
      then "core"
      else elemAt splitApiVersion 0;
    version =
      if length splitApiVersion < 2
      then elemAt splitApiVersion 0
      else elemAt splitApiVersion 1;
    kind = object.kind;
  };
}
