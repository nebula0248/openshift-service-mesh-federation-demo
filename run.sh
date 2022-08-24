#!/bin/sh

#####################################################
#                                                   #
#       Variable, update based on your needs        #
#                                                   #
#####################################################
MESH_1_OCP_SERVER_URL="https://api.XXX:6443"
MESH_1_OCP_TOKEN="sha256~XXX"

MESH_2_OCP_SERVER_URL="https://api.XXX:6443"
MESH_2_OCP_TOKEN="sha256~XXX"

MESH_1_HELM_RELEASE_TO_BE_STORED_NAMESPACE="default" # Make sure you have this namepspace pre-created in your Mesh 1 OCP cluster.
MESH_1_HELM_RELEASE_NAME="ossm-federation-demo-mesh-1"

MESH_2_HELM_RELEASE_TO_BE_STORED_NAMESPACE="default" # Make sure you have this namepspace pre-created in your Mehs 2 OCP cluster.
MESH_2_HELM_RELEASE_NAME="ossm-federation-demo-mesh-2"


#####################################################
#                                                   #
#        Internal variables, do not modify          #
#                                                   #
#####################################################
MESH_1_ISTIO_CTL_PLANE_NS=$(grep "local-mesh-ctl-plane-namespace" ./helm/values-mesh-1.yaml | sed 's/local-mesh-ctl-plane-namespace: //')
MESH_2_ISTIO_CTL_PLANE_NS=$(grep "local-mesh-ctl-plane-namespace" ./helm/values-mesh-2.yaml | sed 's/local-mesh-ctl-plane-namespace: //')
MESH_1_ISTIO_CTL_PLANE_NAME=$(grep "local-mesh-name" ./helm/values-mesh-1.yaml | sed 's/local-mesh-name: //')
MESH_2_ISTIO_CTL_PLANE_NAME=$(grep "local-mesh-name" ./helm/values-mesh-2.yaml | sed 's/local-mesh-name: //')
MESH_1_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP=$(grep "remote-mesh-root-cert-configmap-name" ./helm/values-mesh-1.yaml | sed 's/remote-mesh-root-cert-configmap-name: //')
MESH_2_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP=$(grep "remote-mesh-root-cert-configmap-name" ./helm/values-mesh-2.yaml | sed 's/remote-mesh-root-cert-configmap-name: //')
MESH_1_BOOKINFO_NS=$(grep "local-mesh-bookinfo-namespace" ./helm/values-mesh-1.yaml | sed 's/local-mesh-bookinfo-namespace: //')
MESH_2_BOOKINFO_NS=$(grep "local-mesh-bookinfo-namespace" ./helm/values-mesh-2.yaml | sed 's/local-mesh-bookinfo-namespace: //')


install_demo () {
    local TIME_COUNTER
    local MESH_1_ISTIO_ROOT_CERT
    local MESH_2_ISTIO_ROOT_CERT
    local MESH_1_ISTIO_INGRESSGW_URL
    local MESH_2_ISTIO_INGRESSGW_URL
    
    # Install the Helm resources for mesh 1
    echo_bold "Trying to install Helm chart for mesh 1..."
    run_and_log "oc login --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
    run_and_log "oc project $MESH_1_HELM_RELEASE_TO_BE_STORED_NAMESPACE"
    run_and_log "helm install $MESH_1_HELM_RELEASE_NAME -f helm/values-mesh-1.yaml ./helm"

    # Wait until mesh 1's Istio control plane is ready and installed
    echo_bold "Wait for mesh 1's Istio control plane installation to complete..."
    TIME_COUNTER=1
    while true; do
        sleep 1
        if [ $(oc get ServiceMeshControlPlane ${MESH_1_ISTIO_CTL_PLANE_NAME} -n ${MESH_1_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.conditions[0].reason}") == "InstallSuccessful" ]; then
            printf "\tService mesh for mesh 1 installed successfully!\n\n"
            break
        else
            printf "\tWaited ${TIME_COUNTER}s...\n"
            ((TIME_COUNTER=TIME_COUNTER+1))
        fi
    done

    # Obtain the mesh 1's Istio control plane root cert
    echo_bold "Obtaining the mesh 1's Istio root certificate..."
    MESH_1_ISTIO_ROOT_CERT=$(oc get configmap istio-ca-root-cert -n $MESH_1_ISTIO_CTL_PLANE_NS -o "jsonpath={.data['root-cert\.pem']}")
    echo_bold "Mesh 1 Istio root certificate:"
    echo "${MESH_1_ISTIO_ROOT_CERT}"
    echo "${MESH_1_ISTIO_ROOT_CERT}" > temp-mesh-1-istio-root-cert.pem
    printf "\n"

    # Install the Helm resources for mesh 2
    echo_bold "Trying to install Helm chart for mesh 2..."
    run_and_log "oc login --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
    run_and_log "oc project $MESH_2_HELM_RELEASE_TO_BE_STORED_NAMESPACE"
    run_and_log "helm install $MESH_2_HELM_RELEASE_NAME -f helm/values-mesh-2.yaml ./helm"

    # Wait until mesh 2's Istio control plane is ready and installed
    echo_bold "Wait for mesh 2's Istio control plane installation to complete..."
    TIME_COUNTER=1
    while true; do
        sleep 1
        if [ $(oc get ServiceMeshControlPlane ${MESH_2_ISTIO_CTL_PLANE_NAME} -n ${MESH_2_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.conditions[0].reason}") == "InstallSuccessful" ]; then
            printf "\tService mesh for mesh 2 installed successfully!\n\n"
            break
        else
            printf "\tWaited ${TIME_COUNTER}s...\n"
            ((TIME_COUNTER=TIME_COUNTER+1))
        fi
    done

    # Obtain the mesh 2's Istio control plane root cert
    echo_bold "Obtaining the mesh 2's Istio root certificate..."
    MESH_2_ISTIO_ROOT_CERT=$(oc get configmap istio-ca-root-cert -n $MESH_2_ISTIO_CTL_PLANE_NS -o "jsonpath={.data['root-cert\.pem']}")
    echo_bold "Mesh 2 Istio root certificate:"
    echo "${MESH_2_ISTIO_ROOT_CERT}"
    echo "${MESH_2_ISTIO_ROOT_CERT}" > temp-mesh-2-istio-root-cert.pem
    printf "\n"

    # Exchange service meshes root CA certificates and create ConfigMap objects in the opposite remote meshes
    # Starts with mesh 1, save mesh 2's root cert as ConfigMap in mesh 1
    echo_bold "Inject mesh 2's Istio root cert into mesh 1..."
    run_and_log "oc login --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
    run_and_log "oc create configmap $MESH_1_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP -n $MESH_1_ISTIO_CTL_PLANE_NS --from-file=root-cert.pem=temp-mesh-2-istio-root-cert.pem"

    # Then, inject mesh 1's root cert as ConfigMap in mesh 2
    echo_bold "Inject mesh 1's Istio root cert into mesh 2..."
    run_and_log "oc login --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
    run_and_log "oc create configmap $MESH_2_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP -n $MESH_2_ISTIO_CTL_PLANE_NS --from-file=root-cert.pem=temp-mesh-1-istio-root-cert.pem"

    # Complete, delete those temp files
    rm temp-mesh-1-istio-root-cert.pem
    rm temp-mesh-2-istio-root-cert.pem
    echo_bold "OSSM and bookinfo app installation completed. You may now check the status of your ServiceMeshPeer objects to make sure the federation is established."
    printf "\n"

    # Scale all bookinfo namespace pods up and get the product page URL
    echo_bold "Prepare bookinfo application for mesh 1..."
    run_and_log "oc login --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
    MESH_1_ISTIO_INGRESSGW_URL="http://$(oc get route istio-ingressgateway -n $MESH_1_ISTIO_CTL_PLANE_NS -o 'jsonpath={.spec.host}')"
    run_and_log "oc set env deployment/random-http-traffic-generator -n $MESH_1_BOOKINFO_NS ENV_CURL_URL=$MESH_1_ISTIO_INGRESSGW_URL/productpage" # Make the traffic generator call the Istio gateway
    run_and_log "oc scale deployment -n $MESH_1_BOOKINFO_NS --replicas=1 --all" # Start all deployments

    echo_bold "Prepare bookinfo application for mesh 2..."
    run_and_log "oc login --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
    MESH_2_ISTIO_INGRESSGW_URL="http://$(oc get route istio-ingressgateway -n $MESH_2_ISTIO_CTL_PLANE_NS -o 'jsonpath={.spec.host}')"
    run_and_log "oc set env deployment/random-http-traffic-generator -n $MESH_2_BOOKINFO_NS ENV_CURL_URL=$MESH_2_ISTIO_INGRESSGW_URL/productpage" # Make the traffic generator call the Istio gateway
    run_and_log "oc scale deployment -n $MESH_2_BOOKINFO_NS --replicas=1 --all" # Start all deployments

    # All completed
    echo_bold "********************************* Installation completed! ****************************************"
    echo_bold "You may now check your ServiceMeshPeer status to confirm the connectivities between meshes are up."
    echo_bold "The traffic generator will continuously call your Bookinfo application to simulate traffic."
    echo_bold "You may scale out the traffic generator if needed, or scale down deployments to simulate failure."
    printf "\n"
    echo "Mesh 1's Bookinfo App: $MESH_1_ISTIO_INGRESSGW_URL/productpage"
    echo "Mesh 2's Bookinfo App: $MESH_2_ISTIO_INGRESSGW_URL/productpage"
}

uninstall_demo () {
    # Uninstall the Helm resources for mesh 1
    echo_bold "Trying to uninstall Helm chart for mesh 1..."
    run_and_log "oc login --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
    run_and_log "oc project $MESH_1_HELM_RELEASE_TO_BE_STORED_NAMESPACE"
    run_and_log "helm uninstall $MESH_1_HELM_RELEASE_NAME"

    # Uninstall the Helm resources for mesh 2
    echo_bold "Trying to uninstall Helm chart for mesh 2..."
    run_and_log "oc login --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
    run_and_log "oc project $MESH_2_HELM_RELEASE_TO_BE_STORED_NAMESPACE"
    run_and_log "helm uninstall $MESH_2_HELM_RELEASE_NAME"

    # Complete
    echo_bold "All helm charts for both meshes are deleted."
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