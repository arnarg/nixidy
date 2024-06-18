{
  lib,
  config,
  ...
}: {
  defaults = with lib;
    map (
      type: let
        parts = splitString "/" type;
      in {
        group = elemAt parts 0;
        version = elemAt parts 1;
        kind = elemAt parts 2;
        default = {
          metadata.namespace = lib.mkDefault config.namespace;
        };
      }
    )
    [
      "core/v1/Binding"
      "core/v1/ConfigMap"
      "core/v1/Endpoints"
      "core/v1/Event"
      "core/v1/LimitRange"
      "core/v1/PersistentVolumeClaim"
      "core/v1/Pod"
      "core/v1/PodTemplate"
      "core/v1/ReplicationController"
      "core/v1/ResourceQuota"
      "core/v1/Secret"
      "core/v1/Service"
      "core/v1/ServiceAccount"
      "apps/v1/ControllerRevision"
      "apps/v1/DaemonSet"
      "apps/v1/Deployment"
      "apps/v1/ReplicaSet"
      "apps/v1/StatefulSet"
      "authorization.k8s.io/v1/LocalSubjectAccessReview"
      "autoscaling/v2/HorizontalPodAutoscaler"
      "batch/v1/CronJob"
      "batch/v1/Job"
      "coordination.k8s.io/v1/Lease"
      "discovery.k8s.io/v1/EndpointSlice"
      "events.k8s.io/v1/Event"
      "networking.k8s.io/v1/Ingress"
      "networking.k8s.io/v1/NetworkPolicy"
      "policy/v1/PodDisruptionBudget"
      "rbac.authorization.k8s.io/v1/RoleBinding"
      "rbac.authorization.k8s.io/v1/Role"
      "storage.k8s.io/v1/CSIStorageCapacity"
    ];
}
