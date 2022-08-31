#!/bin/sh

#####################################################
#                                                   #
#       Variable, update based on your needs        #
#                                                   #
#####################################################
MESH_1_OCP_SERVER_URL="https://XXXXX"
MESH_1_OCP_TOKEN="sha256~XXXXX"

MESH_2_OCP_SERVER_URL="https://XXXXX"
MESH_2_OCP_TOKEN="sha256~XXXXX"

MESH_1_HELM_RELEASE_NAMESPACE="peter-ossm-helm"
MESH_1_HELM_RELEASE_NAME="ossm-federation-demo-mesh-1"

MESH_2_HELM_RELEASE_NAMESPACE="peter-ossm-helm"
MESH_2_HELM_RELEASE_NAME="ossm-federation-demo-mesh-2"


#####################################################
#                                                   #
#        Internal variables, do not modify          #
#                                                   #
#####################################################
MESH_1_ISTIO_CTL_PLANE_NS=$(grep "^local-mesh-ctl-plane-namespace" ./helm/values-mesh-1.yaml | sed 's/local-mesh-ctl-plane-namespace: //')
MESH_2_ISTIO_CTL_PLANE_NS=$(grep "^local-mesh-ctl-plane-namespace" ./helm/values-mesh-2.yaml | sed 's/local-mesh-ctl-plane-namespace: //')
MESH_1_ISTIO_CTL_PLANE_NAME=$(grep "^local-mesh-name" ./helm/values-mesh-1.yaml | sed 's/local-mesh-name: //')
MESH_2_ISTIO_CTL_PLANE_NAME=$(grep "^local-mesh-name" ./helm/values-mesh-2.yaml | sed 's/local-mesh-name: //')
MESH_1_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP=$(grep "^remote-mesh-root-cert-configmap-name" ./helm/values-mesh-1.yaml | sed 's/remote-mesh-root-cert-configmap-name: //')
MESH_2_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP=$(grep "^remote-mesh-root-cert-configmap-name" ./helm/values-mesh-2.yaml | sed 's/remote-mesh-root-cert-configmap-name: //')
MESH_1_BOOKINFO_NS=$(grep "^local-mesh-bookinfo-namespace" ./helm/values-mesh-1.yaml | sed 's/local-mesh-bookinfo-namespace: //')
MESH_2_BOOKINFO_NS=$(grep "^local-mesh-bookinfo-namespace" ./helm/values-mesh-2.yaml | sed 's/local-mesh-bookinfo-namespace: //')
MESH_1_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD=$(grep "^local-and-remote-connectivity-method" ./helm/values-mesh-1.yaml | sed 's/local-and-remote-connectivity-method: //')
MESH_2_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD=$(grep "^local-and-remote-connectivity-method" ./helm/values-mesh-2.yaml | sed 's/local-and-remote-connectivity-method: //')
MESH_1_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER=$(grep "^local-mesh-openshift-cloud-provider" ./helm/values-mesh-1.yaml | sed 's/local-mesh-openshift-cloud-provider: //')
MESH_2_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER=$(grep "^local-mesh-openshift-cloud-provider" ./helm/values-mesh-2.yaml | sed 's/local-mesh-openshift-cloud-provider: //')
MESH_1_REMOTE_MESH_NAME=$(grep "^remote-mesh-name" ./helm/values-mesh-1.yaml | sed 's/remote-mesh-name: //')
MESH_2_REMOTE_MESH_NAME=$(grep "^remote-mesh-name" ./helm/values-mesh-2.yaml | sed 's/remote-mesh-name: //')

install_demo () {
    local TIME_COUNTER
    local MESH_1_ISTIO_ROOT_CERT
    local MESH_2_ISTIO_ROOT_CERT
    local MESH_1_ISTIO_INGRESSGW_URL
    local MESH_2_ISTIO_INGRESSGW_URL
    local MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL
    local MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL

    # Check if both meshes are using the same connectivity method to connect (just to simplify the demo)
    if [[ "$MESH_1_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD" != "$MESH_2_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD" ]]
    then
        echo_bold "ERROR: To make the demo simple, we do not allow meshes to have different ways to peer. Make sure both meshes has the same local-and-remote-connectivity-method value set in Helm chart."
        return -1
    fi
    
    # Install the Helm resources for mesh 1
    echo_bold "Trying to install Helm chart for mesh 1..."
    run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
    oc get "project/$MESH_1_HELM_RELEASE_NAMESPACE" > /dev/null 2>&1
    if [ "$?" != "0" ]; then 
        echo_bold "Project $MESH_1_HELM_RELEASE_NAMESPACE not yet exist... Create now"
        run_and_log "oc new-project $MESH_1_HELM_RELEASE_NAMESPACE"
    fi
    run_and_log "oc project $MESH_1_HELM_RELEASE_NAMESPACE"
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

    # If it runs on public cloud and use LoadBalancer to expose mesh ingress gateway, obtain the dynamically
    # generated cloud load balancer URL and inject into ServiceMeshPeer object later
    if [[ "$MESH_1_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD" == "LoadBalancer" ]]
    then
        echo_bold "Trying to get mesh 1's ingress gateway cloud load balancer's URL..."

        # For AWS
        if [[ "$MESH_1_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER" == "AWS" ]]
        then
            echo_bold "Getting the ingress gateway's URL from AWS..."
            TIME_COUNTER=1
            while true; do
                sleep 1
                MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL=$(oc get svc ${MESH_1_REMOTE_MESH_NAME}-ingress -n ${MESH_1_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.loadBalancer.ingress[0].hostname}")
                if [[ "$MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL" == *"amazonaws.com" ]]; then
                    printf "\tAWS Load Balancer URL obtained: $MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL\n\n"
                    break
                else
                    printf "\tWaited ${TIME_COUNTER}s...\n"
                    ((TIME_COUNTER=TIME_COUNTER+1))
                fi
            done
        
        # For Azure
        elif [[ "$MESH_1_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER" == "Azure" ]]
        then
            echo_bold "Getting the ingress gateway's URL from Azure..."
            TIME_COUNTER=1
            while true; do
                sleep 1
                MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL=$(oc get svc ${MESH_1_REMOTE_MESH_NAME}-ingress -n ${MESH_1_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.loadBalancer.ingress[0].ip}")
                if [ ! -z "$MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL" ]; then
                    printf "\tAzure Load Balancer URL obtained: $MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL\n\n"
                    break
                else
                    printf "\tWaited ${TIME_COUNTER}s...\n"
                    ((TIME_COUNTER=TIME_COUNTER+1))
                fi
            done
        fi
    fi
    
    # Install the Helm resources for mesh 2
    echo_bold "Trying to install Helm chart for mesh 2..."
    run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
    oc get "project/$MESH_2_HELM_RELEASE_NAMESPACE" > /dev/null 2>&1
    if [ "$?" != "0" ]; then 
        echo_bold "Project $MESH_2_HELM_RELEASE_NAMESPACE not yet exist... Create now"
        run_and_log "oc new-project $MESH_2_HELM_RELEASE_NAMESPACE"
    fi
    run_and_log "oc project $MESH_2_HELM_RELEASE_NAMESPACE"
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

    # If it runs on public cloud and use LoadBalancer to expose mesh ingress gateway, obtain the dynamically
    # generated cloud load balancer URL and inject into ServiceMeshPeer object later
    if [[ "$MESH_2_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD" == "LoadBalancer" ]]
    then
        echo_bold "Trying to get mesh 2's ingress gateway cloud load balancer's URL..."

        # For AWS
        if [[ "$MESH_2_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER" == "AWS" ]]
        then
            echo_bold "Getting the ingress gateway's URL from AWS..."
            TIME_COUNTER=1
            while true; do
                sleep 1
                MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL=$(oc get svc ${MESH_2_REMOTE_MESH_NAME}-ingress -n ${MESH_2_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.loadBalancer.ingress[0].hostname}")
                if [[ "$MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL" == *"amazonaws.com" ]]; then
                    printf "\tAWS Load Balancer URL obtained: $MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL\n\n"
                    break
                else
                    printf "\tWaited ${TIME_COUNTER}s...\n"
                    ((TIME_COUNTER=TIME_COUNTER+1))
                fi
            done
        
        # For Azure
        elif [[ "$MESH_2_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER" == "Azure" ]]
        then
            echo_bold "Getting the ingress gateway's URL from Azure..."
            TIME_COUNTER=1
            while true; do
                sleep 1
                MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL=$(oc get svc ${MESH_2_REMOTE_MESH_NAME}-ingress -n ${MESH_2_ISTIO_CTL_PLANE_NS} -o "jsonpath={.status.loadBalancer.ingress[0].ip}")
                if [ ! -z "$MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL" ]; then
                    printf "\tAzure Load Balancer URL obtained: $MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL\n\n"
                    break
                else
                    printf "\tWaited ${TIME_COUNTER}s...\n"
                    ((TIME_COUNTER=TIME_COUNTER+1))
                fi
            done
        fi
    fi

    # Exchange service meshes root CA certificates and create ConfigMap objects in the opposite remote meshes
    # Starts with mesh 1, save mesh 2's root cert as ConfigMap in mesh 1
    echo_bold "Inject mesh 2's Istio root cert into mesh 1..."
    run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
    run_and_log "oc create configmap $MESH_1_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP -n $MESH_1_ISTIO_CTL_PLANE_NS --from-file=root-cert.pem=temp-mesh-2-istio-root-cert.pem"

    # Then, inject mesh 1's root cert as ConfigMap in mesh 2
    echo_bold "Inject mesh 1's Istio root cert into mesh 2..."
    run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
    run_and_log "oc create configmap $MESH_2_REMOTE_ISTIO_ROOT_CERT_CONFIGMAP -n $MESH_2_ISTIO_CTL_PLANE_NS --from-file=root-cert.pem=temp-mesh-1-istio-root-cert.pem"

    # Complete, delete those temp files
    rm temp-mesh-1-istio-root-cert.pem
    rm temp-mesh-2-istio-root-cert.pem
    echo_bold "OSSM and bookinfo app installation completed. You may now check the status of your ServiceMeshPeer objects to make sure the federation is established."
    printf "\n"

    # If it runs on public cloud and use LoadBalancer to expose mesh ingress gateway, now is the time
    # to inject back the cloud load balanacer URLs into both meshes
    # This if statement only checkes mesh_1 value equality since we have made use mesh_1 and mesh_2
    # connectivity method value must be the same
    if [[ "$MESH_1_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD" == "LoadBalancer" ]]
    then
        echo_bold "Now it is the time to inject the cloud load balancers' URL into both end meshes..."

        echo_bold "Inject mesh 2's load balancer URL into mesh 1..."
        run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
        run_and_log "oc patch ServiceMeshPeer $MESH_1_REMOTE_MESH_NAME -n $MESH_1_ISTIO_CTL_PLANE_NS --type json -p '[{\"op\":\"replace\",\"path\":\"/spec/remote/addresses/0\",\"value\":\"$MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL\"}]'"

        echo_bold "Inject mesh 1's load balancer URL into mesh 2..."
        run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
        run_and_log "oc patch ServiceMeshPeer $MESH_2_REMOTE_MESH_NAME -n $MESH_2_ISTIO_CTL_PLANE_NS --type json -p '[{\"op\":\"replace\",\"path\":\"/spec/remote/addresses/0\",\"value\":\"$MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL\"}]'"
    fi

    # Scale all bookinfo namespace pods up and get the product page URL
    echo_bold "Prepare bookinfo application for mesh 1..."
    run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
    MESH_1_ISTIO_INGRESSGW_URL="http://$(oc get route istio-ingressgateway -n $MESH_1_ISTIO_CTL_PLANE_NS -o 'jsonpath={.spec.host}')"
    run_and_log "oc set env deployment/random-http-traffic-generator -n $MESH_1_BOOKINFO_NS ENV_CURL_URL=$MESH_1_ISTIO_INGRESSGW_URL/productpage" # Make the traffic generator call the Istio gateway
    run_and_log "oc scale deployment -n $MESH_1_BOOKINFO_NS --replicas=1 --all" # Start all deployments

    echo_bold "Prepare bookinfo application for mesh 2..."
    run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
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
    run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL"
    run_and_log "oc project $MESH_1_HELM_RELEASE_NAMESPACE"
    run_and_log "helm uninstall $MESH_1_HELM_RELEASE_NAME"

    # Uninstall the Helm resources for mesh 2
    echo_bold "Trying to uninstall Helm chart for mesh 2..."
    run_and_log "oc login --insecure-skip-tls-verify=true --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL"
    run_and_log "oc project $MESH_2_HELM_RELEASE_NAMESPACE"
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