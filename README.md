# OpenShift Service Mesh Federation Demo

OpenShift Service Mesh Federation allows you to connect services between separate meshes, which also allows the use of Service Mesh features such as authentication, authorization, and traffic management across multiple, distinct administrative domains.

In general, there are 3 ways to implement mesh-to-mesh federation connectivities:
- `ClusterIP` (usually for meshes within the same OpenShift cluster)
- `NodePort` (usually for meshes across 2 OpenShift clusters on-premises)
- `LoadBalancer` (usually for meshes across 2 OpenShift clusters on public cloud providers)

This repo contains scripts and Helm charts to **support you setting up all the above 3 connectivity scenerios** demo quickly and automatically.

> :warning: Please note that all resources provided in this repo are for demo and non-production usage only. Service mesh federation deployment for production requires detailed planning and design. Please do not use this repo directly for any production purpose.

## Prerequisites

Please make sure you have the following prerequisites met before proceed:
- Prepare 1 or 2 **OpenShift v4.6 or above** clusters
- Install **OpenShift Service Mesh operators (v2.1 or above)** and other Service Mesh related operators (e.g. Kiali, Distributed Tracing) according to the OpenShift documentation (https://docs.openshift.com/container-platform/4.10/service_mesh/v2x/installing-ossm.html)
- Read and understand the official OpenShift Service Mesh Federation documentation before proceed (https://docs.openshift.com/container-platform/4.10/service_mesh/v2x/ossm-federation.html#ossm-federation-overview_federation)
- Install **oc CLI** (oc version >=v4.6)
- Install **helm CLI** (helm version >=v3.6)

## How to deploy the demo resources

1. Open and edit `run.sh` and change the values of the following variables **at the top of the script**:

| Variable name  | Description  |
| ------------ | ------------ |
| MESH_1_OCP_SERVER_URL  | Set this to your 1st OpenShift cluster's API 6443 port endpoint (e.g. https://api.ocp-hub.peterho.internal:6443)  |
| MESH_1_OCP_TOKEN  |  Set this to your oc login command's token for authenticating into your 1st OpenShift cluster (e.g. sha256~XXXXX). |
| MESH_2_OCP_SERVER_URL  |  Set this to your 2nd OpenShift cluster's API 6443 port endpoint (e.g. https://api.ocp-spoke-1.peterho.internal:6443) |
| MESH_2_OCP_TOKEN  |  Set this to your oc login command's token for authenticating into your 2nd OpenShift cluster (e.g. sha256~XXXXX). |
|  MESH_1_HELM_RELEASE_TO_BE_STORED_NAMESPACE |  The namespace that our Helm release will be saved to your 1st OpenShift cluster |
|  MESH_1_HELM_RELEASE_NAME | The Helm release name that will be saved to your 1st OpenShift cluster |
|  MESH_2_HELM_RELEASE_TO_BE_STORED_NAMESPACE |  The namespace that our Helm release will be saved to your 2nd OpenShift cluster |
|  MESH_2_HELM_RELEASE_NAME |  The Helm release name that will be saved to your 2nd OpenShift cluster |

**Note: ** If you are going to deploy both service meshes within the same OpenShift cluster (i.e. using ClusterIP as the mesh-to-mesh connectivity). Set `MESH_2_OCP_SERVER_URL` and `MESH_2_OCP_TOKEN` having the same value as `MESH_1_OCP_SERVER_URL` and `MESH_1_OCP_TOKEN` respectively.