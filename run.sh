#!/bin/sh

#####################################################
#                                                   #
#       Variable, update based on your needs        #
#                                                   #
#####################################################
CLUSTER_1_OCP_SERVER_URL="https://api.XXXXXX:6443"
CLUSTER_1_OCP_TOKEN="sha256~XXXXX"

CLUSTER_2_OCP_SERVER_URL="https://api.XXXXXX:6443"
CLUSTER_2_OCP_TOKEN="sha256~XXXXXX"

HELM_RELEASE_TO_BE_STORED_NAMESPACE="default"
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


install_demo() {
    local TIME_COUNTER
    local CLUSTER_1_ISTIO_ROOT_CERT
    local CLUSTER_2_ISTIO_ROOT_CERT
    
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
        if [ $(oc get ServiceMeshControlPlane ${CLUSTER_1_ISTIO_CTL_PLANE_NAME} -n ${CLUSTER_1_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.conditions[0].reason}") = "InstallSuccessful" ]; then
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
        if [ $(oc get ServiceMeshControlPlane ${CLUSTER_2_ISTIO_CTL_PLANE_NAME} -n ${CLUSTER_2_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.conditions[0].reason}") = "InstallSuccessful" ]; then
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
    echo_bold "Completed. Please check you OpenShift Service Mesh Federation installation."
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

printf "Please enter the option number to select: \n"
printf "\t1. Install the demo resources\n"
printf "\t2. Uninstall the demo resources\n"
read -p "Please input: " option_number

if [ $option_number == 1 ]
then
    install_demo
elif [ $option_number == 2 ]
then
    uninstall_demo
else
    echo "ERROR: Unknown option number. Please run again and enter a correct number."
fi