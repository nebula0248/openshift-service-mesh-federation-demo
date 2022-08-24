#!/bin/sh

#####################################################
#                                                   #
#       Variable, update based on your needs        #
#                                                   #
#####################################################
CLUSTER_1_OCP_SERVER_URL="https://api.YOUR_OCP_CLUSTER1:6443"
CLUSTER_1_OCP_TOKEN="sha256~XXXXX"

CLUSTER_2_OCP_SERVER_URL="https://api.YOUR_OCP_CLUSTER2:6443"
CLUSTER_2_OCP_TOKEN="sha256~XXXXX"

HELM_RELEASE_TO_BE_STORED_NAMESPACE="default" # Make sure you have this namepspace pre-created in your cluster.
HELM_RELEASE_NAME="ossm-federation-demo"


#####################################################
#                                                   #
#        Internal variables, do not modify          #
#                                                   #
#####################################################
CLUSTER_1_ISTIO_CTL_PLANE_NS=$(grep "local-mesh-ctl-plane-namespace" ./helm/values-cluster-1.yaml | sed 's/local-mesh-ctl-plane-namespace: //')
CLUSTER_2_ISTIO_CTL_PLANE_NS=$(grep "local-mesh-ctl-plane-namespace" ./helm/values-cluster-2.yaml | sed 's/local-mesh-ctl-plane-namespace: //')
CLUSTER_1_ISTIO_CTL_PLANE_NAME=$(grep "local-mesh-name" ./helm/values-cluster-1.yaml | sed 's/local-mesh-name: //')
CLUSTER_2_ISTIO_CTL_PLANE_NAME=$(grep "local-mesh-name" ./helm/values-cluster-2.yaml | sed 's/local-mesh-name: //')
CLUSTER_1_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP=$(grep "remote-mesh-root-cert-configmap-name" ./helm/values-cluster-1.yaml | sed 's/remote-mesh-root-cert-configmap-name: //')
CLUSTER_2_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP=$(grep "remote-mesh-root-cert-configmap-name" ./helm/values-cluster-2.yaml | sed 's/remote-mesh-root-cert-configmap-name: //')
CLUSTER_1_BOOKINFO_NS=$(grep "local-mesh-bookinfo-namespace" ./helm/values-cluster-1.yaml | sed 's/local-mesh-bookinfo-namespace: //')
CLUSTER_2_BOOKINFO_NS=$(grep "local-mesh-bookinfo-namespace" ./helm/values-cluster-2.yaml | sed 's/local-mesh-bookinfo-namespace: //')


install_demo () {
    local TIME_COUNTER
    local CLUSTER_1_ISTIO_ROOT_CERT
    local CLUSTER_2_ISTIO_ROOT_CERT
    local CLUSTER_1_ISTIO_INGRESSGW_URL
    local CLUSTER_2_ISTIO_INGRESSGW_URL
    
    # Install the Helm resources in cluster 1
    echo_bold "Trying to install Helm chart in Cluster 1..."
    run_and_log "oc login --token=$CLUSTER_1_OCP_TOKEN --server=$CLUSTER_1_OCP_SERVER_URL"
    run_and_log "oc project $HELM_RELEASE_TO_BE_STORED_NAMESPACE"
    run_and_log "helm install $HELM_RELEASE_NAME -f helm/values-cluster-1.yaml ./helm"

    # Wait until cluster 1's Istio control plane is ready and installed
    echo_bold "Wait for Cluster 1's Istio control plane installation to complete..."
    TIME_COUNTER=1
    while true; do
        sleep 1
        if [ $(oc get ServiceMeshControlPlane ${CLUSTER_1_ISTIO_CTL_PLANE_NAME} -n ${CLUSTER_1_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.conditions[0].reason}") == "InstallSuccessful" ]; then
            printf "\tService mesh at cluster 1 installed successfully!\n\n"
            break
        else
            printf "\tWaited ${TIME_COUNTER}s...\n"
            ((TIME_COUNTER=TIME_COUNTER+1))
        fi
    done

    # Obtain the cluster 1's Istio control plane root cert
    echo_bold "Obtaining the Cluster 1's Istio root certificate..."
    CLUSTER_1_ISTIO_ROOT_CERT=$(oc get configmap istio-ca-root-cert -n $CLUSTER_1_ISTIO_CTL_PLANE_NS -o "jsonpath={.data['root-cert\.pem']}")
    echo_bold "Cluster 1 Istio root certificate:"
    echo "${CLUSTER_1_ISTIO_ROOT_CERT}"
    echo "${CLUSTER_1_ISTIO_ROOT_CERT}" > temp-cluster-1-istio-root-cert.pem
    printf "\n"

    # Install the Helm resources in cluster 2
    echo_bold "Trying to install Helm chart in Cluster 2..."
    run_and_log "oc login --token=$CLUSTER_2_OCP_TOKEN --server=$CLUSTER_2_OCP_SERVER_URL"
    run_and_log "oc project $HELM_RELEASE_TO_BE_STORED_NAMESPACE"
    run_and_log "helm install $HELM_RELEASE_NAME -f helm/values-cluster-2.yaml ./helm"

    # Wait until cluster 2's Istio control plane is ready and installed
    echo_bold "Wait for Cluster 2's Istio control plane installation to complete..."
    TIME_COUNTER=1
    while true; do
        sleep 1
        if [ $(oc get ServiceMeshControlPlane ${CLUSTER_2_ISTIO_CTL_PLANE_NAME} -n ${CLUSTER_2_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.conditions[0].reason}") == "InstallSuccessful" ]; then
            printf "\tService mesh at cluster 2 installed successfully!\n\n"
            break
        else
            printf "\tWaited ${TIME_COUNTER}s...\n"
            ((TIME_COUNTER=TIME_COUNTER+1))
        fi
    done

    # Obtain the cluster 2's Istio control plane root cert
    echo_bold "Obtaining the Cluster 2's Istio root certificate..."
    CLUSTER_2_ISTIO_ROOT_CERT=$(oc get configmap istio-ca-root-cert -n $CLUSTER_2_ISTIO_CTL_PLANE_NS -o "jsonpath={.data['root-cert\.pem']}")
    echo_bold "Cluster 2 Istio root certificate:"
    echo "${CLUSTER_2_ISTIO_ROOT_CERT}"
    echo "${CLUSTER_2_ISTIO_ROOT_CERT}" > temp-cluster-2-istio-root-cert.pem
    printf "\n"

    # Exchange service meshes root CA certificates and create ConfigMap objects in the opposite remote meshes
    # Starts with cluster 1, save cluster 2's root cert as ConfigMap in cluster 1
    echo_bold "Inject cluster 2's Istio root cert into cluster 1..."
    run_and_log "oc login --token=$CLUSTER_1_OCP_TOKEN --server=$CLUSTER_1_OCP_SERVER_URL"
    run_and_log "oc create configmap $CLUSTER_1_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP -n $CLUSTER_1_ISTIO_CTL_PLANE_NS --from-file=root-cert.pem=temp-cluster-2-istio-root-cert.pem"

    # Then, inject cluster 1's root cert as ConfigMap in cluster 2
    echo_bold "Inject cluster 1's Istio root cert into cluster 2..."
    run_and_log "oc login --token=$CLUSTER_2_OCP_TOKEN --server=$CLUSTER_2_OCP_SERVER_URL"
    run_and_log "oc create configmap $CLUSTER_2_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP -n $CLUSTER_2_ISTIO_CTL_PLANE_NS --from-file=root-cert.pem=temp-cluster-1-istio-root-cert.pem"

    # Complete, delete those temp files
    rm temp-cluster-1-istio-root-cert.pem
    rm temp-cluster-2-istio-root-cert.pem
    echo_bold "OSSM and bookinfo app installation completed. You may now check the status of your ServiceMeshPeer objects to make sure the federation is established."
    printf "\n"

    # Scale all bookinfo namespace pods up and get the product page URL
    echo_bold "Prepare bookinfo application for cluster 1..."
    run_and_log "oc login --token=$CLUSTER_1_OCP_TOKEN --server=$CLUSTER_1_OCP_SERVER_URL"
    CLUSTER_1_ISTIO_INGRESSGW_URL="http://$(oc get route istio-ingressgateway -n $CLUSTER_1_ISTIO_CTL_PLANE_NS -o 'jsonpath={.spec.host}')"
    run_and_log "oc set env deployment/random-http-traffic-generator -n $CLUSTER_1_BOOKINFO_NS ENV_CURL_URL=$CLUSTER_1_ISTIO_INGRESSGW_URL/productpage" # Make the traffic generator call the Istio gateway
    run_and_log "oc scale deployment -n $CLUSTER_1_BOOKINFO_NS --replicas=1 --all" # Start all deployments

    echo_bold "Prepare bookinfo application for cluster 2..."
    run_and_log "oc login --token=$CLUSTER_2_OCP_TOKEN --server=$CLUSTER_2_OCP_SERVER_URL"
    CLUSTER_2_ISTIO_INGRESSGW_URL="http://$(oc get route istio-ingressgateway -n $CLUSTER_2_ISTIO_CTL_PLANE_NS -o 'jsonpath={.spec.host}')"
    run_and_log "oc set env deployment/random-http-traffic-generator -n $CLUSTER_2_BOOKINFO_NS ENV_CURL_URL=$CLUSTER_2_ISTIO_INGRESSGW_URL/productpage" # Make the traffic generator call the Istio gateway
    run_and_log "oc scale deployment -n $CLUSTER_2_BOOKINFO_NS --replicas=1 --all" # Start all deployments

    # All completed
    echo_bold "********************************* Installation completed! ****************************************"
    echo_bold "You may now check your ServiceMeshPeer status to confirm the connectivities between meshes are up."
    echo_bold "The traffic generator will continuously call your Bookinfo application to simulate traffic."
    echo_bold "You may scale out the traffic generator if needed, or scale down deployments to simulate failure."
    printf "\n"
    echo "Cluster 1's Bookinfo App: $CLUSTER_1_ISTIO_INGRESSGW_URL/productpage"
    echo "Cluster 2's Bookinfo App: $CLUSTER_2_ISTIO_INGRESSGW_URL/productpage"
}

uninstall_demo () {
    # Uninstall the Helm resources in cluster 1
    echo_bold "Trying to uninstall Helm chart in Cluster 1..."
    run_and_log "oc login --token=$CLUSTER_1_OCP_TOKEN --server=$CLUSTER_1_OCP_SERVER_URL"
    run_and_log "oc project $HELM_RELEASE_TO_BE_STORED_NAMESPACE"
    run_and_log "helm uninstall $HELM_RELEASE_NAME"

    # Uninstall the Helm resources in cluster 2
    echo_bold "Trying to uninstall Helm chart in Cluster 2..."
    run_and_log "oc login --token=$CLUSTER_2_OCP_TOKEN --server=$CLUSTER_2_OCP_SERVER_URL"
    run_and_log "oc project $HELM_RELEASE_TO_BE_STORED_NAMESPACE"
    run_and_log "helm uninstall $HELM_RELEASE_NAME"

    # Complete
    echo_bold "All helm charts at both clusters are deleted."
}

echo_bold() {
    # Input $1 argument: Message to be printed
    TEXT_BOLD=$(tput bold)
    TEXT_NORMAL=$(tput sgr0)
    printf "${TEXT_BOLD}${1}${TEXT_NORMAL}\n"
}

run_and_log() {
    # Input $1 argument: command to be executed
    echo_bold "${1}"
    eval "${1}"
    printf "\n"
}

if [[ ! -z "$1" ]] && [[ "$1" == "install" ]]
then
    install_demo
elif [[ ! -z "$1" ]] && [[ "$1" == "uninstall" ]]
then
    uninstall_demo
else
    echo "ERROR: Please provide input parameter (install / uninstall)"
fi