# OpenShift Service Mesh Federation Demo

This demo shows how to use OpenShift Service Mesh Federation to establish peering between 2 service meshes. Here we showcase 3 types of mesh-to-mesh federation connectivities:
- `ClusterIP` (usually for meshes within the same OpenShift cluster)
![Alt text](images/clusterip.png?raw=true "Using ClusterIP to connect")
- `LoadBalancer` (usually for meshes across 2 OpenShift clusters on public cloud providers)
![Alt text](images/loadbalancer.png?raw=true "Using ClusterIP to connect")
- `NodePort` (usually for meshes across 2 OpenShift clusters on-premises)
![Alt text](images/nodeport.png?raw=true "Using ClusterIP to connect")

In reality, you do not need to use same type of service exposure for both clusters, and you may use one type at one end and the other type at the opposite end (e.g. cluster A exposes via NodePort, and cluster B exposes via LoadBalancer). However, **to simplify this demo, this demo script assums both ends use the same service exposure type.**

Beside, this demo leverages the well-known Istio demo app, **Bookinfo**, to showcase how to use the **failover capability** (https://docs.openshift.com/container-platform/4.10/service_mesh/v2x/ossm-federation.html#ossm-federation-config-failover-overview_federation) to implement individual app-level failover resilience. With the failover capability provided by the mesh federation, individual apps can now be failed over to another mesh / OpenShift cluster when it is not available.



> :warning: Please note that all resources provided in this repo are for demo and non-production usage only. Service mesh federation deployment for production requires detailed planning and design. Please do not use this repo directly for any production purposes.

## Demo prerequisites

Please make sure you have the following prerequisites met before proceed:
- Prepare 1 or 2 **OpenShift v4.6 or above** clusters. **Both clusters can communicate and have unrestricted Layer 4 connectivity ** (to let Istio gateways communicate with each other)
- Install **OpenShift Service Mesh operator (v2.1 or above)** and other Service Mesh related operators (e.g. Kiali, Distributed Tracing) according to the OpenShift documentation (https://docs.openshift.com/container-platform/4.10/service_mesh/v2x/installing-ossm.html)
- Read and understand the official OpenShift Service Mesh Federation documentation (https://docs.openshift.com/container-platform/4.10/service_mesh/v2x/ossm-federation.html#ossm-federation-overview_federation)
- Install **oc CLI** (oc version >=v4.6)
- Install **helm CLI** (helm version >=v3.6)

## Install the demo resources

1 - Edit `run.sh` and change the values of the following variables located at the top of the script:

| Variable name  | Description  |
| ------------ | ------------ |
| MESH_1_OCP_SERVER_URL  | Set this to your 1st OpenShift cluster's API 6443 port endpoint (e.g. https://api.ocp-hub.peterho.internal:6443)  |
| MESH_1_OCP_TOKEN  |  Set this to your oc login command's token for authenticating into your 1st OpenShift cluster (e.g. sha256~XXXXX). |
| MESH_2_OCP_SERVER_URL  |  Set this to your 2nd OpenShift cluster's API 6443 port endpoint (e.g. https://api.ocp-spoke-1.peterho.internal:6443) |
| MESH_2_OCP_TOKEN  |  Set this to your oc login command's token for authenticating into your 2nd OpenShift cluster (e.g. sha256~XXXXX). |
|  MESH_1_HELM_RELEASE_NAMESPACE |  The namespace that our Helm release will be saved to your 1st OpenShift cluster |
|  MESH_1_HELM_RELEASE_NAME | The Helm release name that will be saved to your 1st OpenShift cluster |
|  MESH_2_HELM_RELEASE_NAMESPACE |  The namespace that our Helm release will be saved to your 2nd OpenShift cluster |
|  MESH_2_HELM_RELEASE_NAME |  The Helm release name that will be saved to your 2nd OpenShift cluster |

> **Note:** If you are going to deploy both service meshes within the same OpenShift cluster (i.e. using ClusterIP as the mesh-to-mesh connectivity). Set `MESH_2_OCP_SERVER_URL` and `MESH_2_OCP_TOKEN` to have the same value as `MESH_1_OCP_SERVER_URL` and `MESH_1_OCP_TOKEN` respectively.

2 - Edit `helm/values-mesh-1.yaml` and `helm/values-mesh-2.yaml`. You may edit the mesh name and the namespace that you want to deploy your service mesh control plane and bookinfo application.
> **Note:** Please make sure you have symatically settings at both YAML files (i.e. the name of the **local mesh** inside **values-mesh-1.yaml** matches the name of the **remote mesh** inside **value-mesh-2.yaml**, etc.)

3 - Inside `helm/values-mesh-1.yaml` and `helm/values-mesh-2.yaml`, select which type of connectivity you want to establish by commenting and uncommenting.
- **For both meshes that stay within the same OpenShift cluster**: Uncomment the lines below the Type 1 comment block, and comment out all other lines below Type 2 and Type 3.

- **For both meshes across 2 OpenShift clusters via LoadBalancer**: Uncomment the lines below the Type 2 comment block, and comment out all other lines below Type 1 and Type 3.

- **For both meshes across 2 OpenShift clusters via NodePort**: Uncomment the lines below the Type 3 comment block, and comment out all other lines below Type 1 and Type 2.

> **Note:**
- If you are using **LoadBalancer** type, change `local-mesh-openshift-cloud-provider` to either `AWS` or `Azure` (this script only supports AWS and Azure). Setting this will make the script provision a public internet-facing load balancer on your cloud provider for federation connectivity.

>- If you are using **NodePort**, change `remote-mesh-peering-addresses` to include a list of IPs or FQDNs that have NodePort exposed for connectivity. In most cases, you may enter a list of worker node IP addresses.

4 - Execute `./run.sh install`.

5 - Enjoy :)

## Uninstall the demo

Simply run `./run.sh uninstall` after you have installed the demo. This will trigger a script to remove all Helm releases.

## Author and contact

If there are any questions or issues, please submit a GitHub issue (much apprecated). Please also feel free to connect with the author (Peter Ho) through LinkedIn here (https://www.linkedin.com/in/peter-ho-man-fai/).