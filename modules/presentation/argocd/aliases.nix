# Back-compat: value-forward each old top-level `applications.<name>.<path>` to
# its new home `applications.<name>.argocd.<path>`. Nested submodules
# (ignoreDifferences, syncPolicy.retry, syncPolicy.managedNamespaceMetadata) are
# aliased at the container level so the whole subtree forwards. Paths mirror
# ./options.nix; keep them in sync.
{ lib, ... }:
{
  imports = map (path: lib.mkRenamedOptionModule path ([ "argocd" ] ++ path)) [
    [ "project" ]
    [ "finalizer" ]
    [ "ignoreDifferences" ]

    # destination.*
    [
      "destination"
      "name"
    ]
    [
      "destination"
      "server"
    ]

    # compareOptions.*
    [
      "compareOptions"
      "serverSideDiff"
    ]
    [
      "compareOptions"
      "includeMutationWebhook"
    ]
    [
      "compareOptions"
      "ignoreExtraneous"
    ]

    # syncPolicy.* (retry/managedNamespaceMetadata aliased at container level)
    [
      "syncPolicy"
      "managedNamespaceMetadata"
    ]
    [
      "syncPolicy"
      "retry"
    ]

    # syncPolicy.autoSync.*
    [
      "syncPolicy"
      "autoSync"
      "enable"
    ]
    [
      "syncPolicy"
      "autoSync"
      "prune"
    ]
    [
      "syncPolicy"
      "autoSync"
      "selfHeal"
    ]

    # syncPolicy.syncOptions.*
    [
      "syncPolicy"
      "syncOptions"
      "applyOutOfSyncOnly"
    ]
    [
      "syncPolicy"
      "syncOptions"
      "createNamespace"
    ]
    [
      "syncPolicy"
      "syncOptions"
      "pruneLast"
    ]
    [
      "syncPolicy"
      "syncOptions"
      "replace"
    ]
    [
      "syncPolicy"
      "syncOptions"
      "serverSideApply"
    ]
    [
      "syncPolicy"
      "syncOptions"
      "failOnSharedResource"
    ]
    [
      "syncPolicy"
      "syncOptions"
      "clientSideApplyMigration"
    ]
  ];
}
