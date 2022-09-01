#!/bin/sh

#####################################################
#                                                   #
#       Variable, update based on your needs        #
#                                                   #
#####################################################
MESH_1_OCP_SERVER_URL="https://XXXXX"
MESH_1_OCP_TOKEN="sha256~XXXXX"
MESH_1_HELM_RELEASE_NAMESPACE="peter-ossm-helm"

MESH_2_OCP_SERVER_URL="https://XXXXX"
MESH_2_OCP_TOKEN="sha256~XXXXX"
MESH_2_HELM_RELEASE_NAMESPACE="peter-ossm-helm"


#####################################################
#                                                   #
#        Internal variables, do not modify          #
#                                                   #
#####################################################
MESH_1_ISTIO_CTL_PLANE_NS=$(grep "^local-mesh-ctl-plane-namespace" ./values-mesh-1.yaml | sed 's/local-mesh-ctl-plane-namespace: //')
MESH_2_ISTIO_CTL_PLANE_NS=$(grep "^local-mesh-ctl-plane-namespace" ./values-mesh-2.yaml | sed 's/local-mesh-ctl-plane-namespace: //')
MESH_1_ISTIO_CTL_PLANE_NAME=$(grep "^local-mesh-name" ./values-mesh-1.yaml | sed 's/local-mesh-name: //')
MESH_2_ISTIO_CTL_PLANE_NAME=$(grep "^local-mesh-name" ./values-mesh-2.yaml | sed 's/local-mesh-name: //')
MESH_1_BOOKINFO_NS=$(grep "^local-mesh-bookinfo-namespace" ./values-mesh-1.yaml | sed 's/local-mesh-bookinfo-namespace: //')
MESH_2_BOOKINFO_NS=$(grep "^local-mesh-bookinfo-namespace" ./values-mesh-2.yaml | sed 's/local-mesh-bookinfo-namespace: //')
MESH_1_REMOTE_MESH_NAME=$(grep "^remote-mesh-name" ./values-mesh-1.yaml | sed 's/remote-mesh-name: //')
MESH_2_REMOTE_MESH_NAME=$(grep "^remote-mesh-name" ./values-mesh-2.yaml | sed 's/remote-mesh-name: //')
MESH_1_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD=$(grep "^local-and-remote-connectivity-method" ./values-mesh-1.yaml | sed 's/local-and-remote-connectivity-method: //')
MESH_2_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD=$(grep "^local-and-remote-connectivity-method" ./values-mesh-2.yaml | sed 's/local-and-remote-connectivity-method: //')
MESH_1_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER=$(grep "^local-mesh-openshift-cloud-provider" ./values-mesh-1.yaml | sed 's/local-mesh-openshift-cloud-provider: //')
MESH_2_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER=$(grep "^local-mesh-openshift-cloud-provider" ./values-mesh-2.yaml | sed 's/local-mesh-openshift-cloud-provider: //')
MESH_1_HELM_CTL_PLANE_RELEASE_NAME="mesh1-ossm-federation-ctl-plane"
MESH_1_HELM_CONNECTIVITY_RELEASE_NAME="mesh1-ossm-federation-connectivity"
MESH_1_HELM_BOOKINFO_RELEASE_NAME="mesh1-ossm-federation-bookinfo"
MESH_2_HELM_CTL_PLANE_RELEASE_NAME="mesh2-ossm-federation-ctl-plane"
MESH_2_HELM_CONNECTIVITY_RELEASE_NAME="mesh2-ossm-federation-connectivity"
MESH_2_HELM_BOOKINFO_RELEASE_NAME="mesh2-ossm-federation-bookinfo"


install_demo () {
    local TIME_COUNTER
    local MESH_1_ISTIO_ROOT_CERT
    local MESH_2_ISTIO_ROOT_CERT
    local MESH_1_ISTIO_INGRESSGW_URL
    local MESH_2_ISTIO_INGRESSGW_URL
    local MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL
    local MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL

    # Mesh1: Ensure service mesh operators are available
    mesh1_execute oc get deployment/istio-operator -n openshift-operators &> /dev/null
    if [[ "$?" != "0" ]]; then
        mesh1_log "OpenShift Service Mesh operator not found. Install the service mesh operators now..."
        mesh1_log_and_execute oc apply -f operators/service-mesh-operators.yaml
        
        mesh1_log "Wait 1 minute to let the operator installation completes..."
        mesh1_log_and_execute sleep 60
    fi

    # Mesh2: Ensure service mesh operators are available
    mesh2_execute oc get deployment/istio-operator -n openshift-operators &> /dev/null
    if [[ "$?" != "0" ]]; then
        mesh2_log "OpenShift Service Mesh operator not found. Install the service mesh operators now..."
        mesh2_log_and_execute oc apply -f operators/service-mesh-operators.yaml
        
        mesh2_log "Wait 1 minute to let the operator installation completes..."
        mesh2_log_and_execute sleep 60
    fi

    # Mesh1: Create necessary namespaces
    mesh1_log "Create namespaces if necessary..."
    mesh1_log_and_execute oc new-project $MESH_1_ISTIO_CTL_PLANE_NS
    mesh1_log_and_execute oc new-project $MESH_1_BOOKINFO_NS

    # Mesh2: Create necessary namespaces
    mesh2_log "Create namespaces if necessary..."
    mesh2_log_and_execute oc new-project $MESH_2_ISTIO_CTL_PLANE_NS
    mesh2_log_and_execute oc new-project $MESH_2_BOOKINFO_NS

    # Mesh1: Install the control plane
    mesh1_log "Trying to install the control plane..."
    mesh1_log_and_execute helm install $MESH_1_HELM_CTL_PLANE_RELEASE_NAME -n $MESH_1_HELM_RELEASE_NAMESPACE --create-namespace -f values-mesh-1.yaml ./helm-control-plane
    
    mesh1_log "Wait until the control plane installation completes..."
    TIME_COUNTER=1
    while true; do
        sleep 1
        if [ $(oc get ServiceMeshControlPlane $MESH_1_ISTIO_CTL_PLANE_NAME -n $MESH_1_ISTIO_CTL_PLANE_NS -o "jsonpath={.status.conditions[0].reason}") == "InstallSuccessful" ]; then
            mesh1_log "Control plane installed successfully!"
            printf "\n"
            break
        fi
    done

    # Mesh2: Install the control plane
    mesh2_log "Trying to install the control plane..."
    mesh2_log_and_execute helm install $MESH_2_HELM_CTL_PLANE_RELEASE_NAME -n $MESH_2_HELM_RELEASE_NAMESPACE --create-namespace -f values-mesh-2.yaml ./helm-control-plane
    
    mesh2_log "Wait until the control plane installation completes..."
    TIME_COUNTER=1
    while true; do
        sleep 1
        if [ $(oc get ServiceMeshControlPlane $MESH_2_ISTIO_CTL_PLANE_NAME -n $MESH_2_ISTIO_CTL_PLANE_NS -o "jsonpath={.status.conditions[0].reason}") == "InstallSuccessful" ]; then
            mesh2_log "Control plane installed successfully!"
            printf "\n"
            break
        fi
    done

    # Mesh1: Get ingress gateway URL when running on cloud and exposes via LoadBalancer
    if [[ "$MESH_1_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD" == "LoadBalancer" ]]; then
        TIME_COUNTER=1

        if [[ "$MESH_1_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER" == "AWS" ]]; then
            mesh1_log "Trying to get the mesh fedeartion ingress gateway's AWS load balancer URL..."
            while true; do
                sleep 1
                MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL=$(mesh1_execute oc get svc $MESH_1_REMOTE_MESH_NAME-ingress -n $MESH_1_ISTIO_CTL_PLANE_NS -o "jsonpath={.status.loadBalancer.ingress[0].hostname}")
                if [[ "$MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL" == *"amazonaws.com" ]]; then
                    mesh1_log "AWS load balancer URL obtained: $MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL"
                    printf "\n"
                    break
                fi
            done
        elif [[ "$MESH_1_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER" == "Azure" ]]; then
            mesh1_log "Trying to get the mesh fedeartion ingress gateway's Azure load balancer URL..."
            while true; do
                sleep 1
                MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL=$(mesh1_execute oc get svc $MESH_1_REMOTE_MESH_NAME-ingress -n $MESH_1_ISTIO_CTL_PLANE_NS -o "jsonpath={.status.loadBalancer.ingress[0].ip}")
                if [[ ! -z "$MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL" ]]; then
                    mesh1_log "Azure load balancer URL obtained: $MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL"
                    printf "\n"
                    break
                fi
            done
        fi
    fi

    # Mesh2: Get ingress gateway URL when running on cloud and exposes via LoadBalancer
    if [[ "$MESH_2_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD" == "LoadBalancer" ]]; then
        TIME_COUNTER=1

        if [[ "$MESH_2_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER" == "AWS" ]]; then
            mesh2_log "Trying to get the mesh fedeartion ingress gateway's AWS load balancer URL..."
            while true; do
                sleep 1
                MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL=$(mesh2_execute oc get svc $MESH_2_REMOTE_MESH_NAME-ingress -n $MESH_2_ISTIO_CTL_PLANE_NS -o "jsonpath={.status.loadBalancer.ingress[0].hostname}")
                if [[ "$MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL" == *"amazonaws.com" ]]; then
                    mesh2_log "AWS load balancer URL obtained: $MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL"
                    printf "\n"
                    break
                fi
            done
        elif [[ "$MESH_2_LOCAL_MESH_OPENSHIFT_CLOUD_PROVIDER" == "Azure" ]]; then
            mesh2_log "Trying to get the mesh fedeartion ingress gateway's Azure load balancer URL..."
            while true; do
                sleep 1
                MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL=$(mesh2_execute oc get svc $MESH_2_REMOTE_MESH_NAME-ingress -n $MESH_2_ISTIO_CTL_PLANE_NS -o "jsonpath={.status.loadBalancer.ingress[0].ip}")
                if [[ ! -z "$MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL" ]]; then
                    mesh2_log "Azure load balancer URL obtained: $MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL"
                    printf "\n"
                    break
                fi
            done
        fi
    fi

    # Mesh1: Obtain control plane's root cert
    mesh1_log "Obtaining the mesh's Istio root certificate..."
    MESH_1_ISTIO_ROOT_CERT=$(mesh1_execute oc get configmap istio-ca-root-cert -n $MESH_1_ISTIO_CTL_PLANE_NS -o jsonpath='{.data.root-cert\.pem}')
    mesh1_log "Here is the certificate obtained:"
    echo "$MESH_1_ISTIO_ROOT_CERT"
    echo "$MESH_1_ISTIO_ROOT_CERT" > temp-mesh-1-istio-root-cert.pem
    printf "\n"

    # Mesh2: Obtain control plane's root cert
    mesh2_log "Obtaining the mesh's Istio root certificate..."
    MESH_2_ISTIO_ROOT_CERT=$(mesh2_execute oc get configmap istio-ca-root-cert -n $MESH_2_ISTIO_CTL_PLANE_NS -o jsonpath='{.data.root-cert\.pem}')
    mesh2_log "Here is the certificate obtained:"
    echo "$MESH_2_ISTIO_ROOT_CERT"
    echo "$MESH_2_ISTIO_ROOT_CERT" > temp-mesh-2-istio-root-cert.pem
    printf "\n"

    # Mesh1: Inject mesh2's control plane root cert
    mesh1_log "Injecting mesh2's control plane root certificate into the control plane namespace..."
    mesh1_log_and_execute oc create configmap $MESH_1_REMOTE_MESH_NAME-ca-root-cert -n $MESH_1_ISTIO_CTL_PLANE_NS --from-file=root-cert.pem=temp-mesh-2-istio-root-cert.pem
    rm temp-mesh-2-istio-root-cert.pem

    # Mesh2: Inject mesh1's control plane root cert
    mesh2_log "Injecting mesh1's control plane root certificate into the control plane namespace..."
    mesh2_log_and_execute oc create configmap $MESH_2_REMOTE_MESH_NAME-ca-root-cert -n $MESH_2_ISTIO_CTL_PLANE_NS --from-file=root-cert.pem=temp-mesh-1-istio-root-cert.pem
    rm temp-mesh-1-istio-root-cert.pem

    # Mesh1: Establish service mesh federation peering
    mesh1_log "Establishing service mesh federation peering with mesh2..."
    mesh1_log_and_execute helm install $MESH_1_HELM_CONNECTIVITY_RELEASE_NAME -n $MESH_1_HELM_RELEASE_NAMESPACE --create-namespace -f values-mesh-1.yaml ./helm-federation

    # Mesh2: Establish service mesh federation peering
    mesh2_log "Establishing service mesh federation peering with mesh1..."
    mesh2_log_and_execute helm install $MESH_2_HELM_CONNECTIVITY_RELEASE_NAME -n $MESH_2_HELM_RELEASE_NAMESPACE --create-namespace -f values-mesh-2.yaml ./helm-federation

    # If the deployment runs on public cloud and thus uses LoadBalancer to expose mesh ingress gateways,
    # now is the time to inject back the cloud load balanacer URLs into both meshes.
    if [[ "$MESH_1_LOCAL_AND_REMOTE_CONNECTIVITY_METHOD" == "LoadBalancer" ]]; then
        # Mesh1: Inject mesh2's ingress gateway URL
        mesh1_log "Injecting mesh2's ingress gateway URL into mesh1's ServiceMeshPeer object..."
        mesh1_log_and_execute oc patch ServiceMeshPeer $MESH_1_REMOTE_MESH_NAME -n $MESH_1_ISTIO_CTL_PLANE_NS --type json -p "[{\"op\":\"replace\",\"path\":\"/spec/remote/addresses/0\",\"value\":\"$MESH_2_LOAD_BALANCER_MESH_INGRESSGW_URL\"}]"

        # Mesh2: Inject mesh1's ingress gateway URL
        mesh2_log "Injecting mesh1's ingress gateway URL into mesh2's ServiceMeshPeer object..."
        mesh2_log_and_execute oc patch ServiceMeshPeer $MESH_2_REMOTE_MESH_NAME -n $MESH_2_ISTIO_CTL_PLANE_NS --type json -p "[{\"op\":\"replace\",\"path\":\"/spec/remote/addresses/0\",\"value\":\"$MESH_1_LOAD_BALANCER_MESH_INGRESSGW_URL\"}]"
    fi

    # Mesh1: Install bookinfo & traffic generator
    mesh1_log "Installing bookinfo app and HTTP traffic generator..."
    mesh1_log_and_execute helm install $MESH_1_HELM_BOOKINFO_RELEASE_NAME -n $MESH_1_HELM_RELEASE_NAMESPACE --create-namespace -f values-mesh-1.yaml ./helm-bookinfo

    # Mesh2: Install bookinfo & traffic generator
    mesh2_log "Installing bookinfo app and HTTP traffic generator..."
    mesh2_log_and_execute helm install $MESH_2_HELM_BOOKINFO_RELEASE_NAME -n $MESH_2_HELM_RELEASE_NAMESPACE --create-namespace -f values-mesh-2.yaml ./helm-bookinfo

    # Mesh1: Make the traffic generator call the mesh's default ingress gateway
    mesh1_log "Making the HTTP traffic generator to call the default Istio ingress gateway..."
    MESH_1_ISTIO_INGRESSGW_URL="http://$(mesh1_execute oc get route istio-ingressgateway -n $MESH_1_ISTIO_CTL_PLANE_NS -o 'jsonpath={.spec.host}')"
    mesh1_log_and_execute "oc set env deployment/random-http-traffic-generator -n $MESH_1_BOOKINFO_NS ENV_CURL_URL=$MESH_1_ISTIO_INGRESSGW_URL/productpage"

    # Mesh2: Make the traffic generator call the mesh's default ingress gateway
    mesh2_log "Making the HTTP traffic generator to call the default Istio ingress gateway..."
    MESH_2_ISTIO_INGRESSGW_URL="http://$(mesh2_execute oc get route istio-ingressgateway -n $MESH_2_ISTIO_CTL_PLANE_NS -o 'jsonpath={.spec.host}')"
    mesh2_log_and_execute "oc set env deployment/random-http-traffic-generator -n $MESH_2_BOOKINFO_NS ENV_CURL_URL=$MESH_2_ISTIO_INGRESSGW_URL/productpage"

    # All completed
    log "-----------------------------------Installation completed! ---------------------------------------"
    log "You may now check your ServiceMeshPeer status to confirm the connectivities between meshes are up."
    log "The traffic generator will continuously call your Bookinfo application to simulate traffic."
    log "You may scale out the traffic generator if needed, or scale down deployments to simulate failure."
    printf "\n"
    log "Mesh 1's Bookinfo App: $MESH_1_ISTIO_INGRESSGW_URL/productpage"
    log "Mesh 2's Bookinfo App: $MESH_2_ISTIO_INGRESSGW_URL/productpage"
}

uninstall_demo () {
    mesh1_log "Uninstall Helm releases..."
    mesh1_log_and_execute helm uninstall $MESH_1_HELM_BOOKINFO_RELEASE_NAME -n $MESH_1_HELM_RELEASE_NAMESPACE
    mesh1_log_and_execute helm uninstall $MESH_1_HELM_CONNECTIVITY_RELEASE_NAME -n $MESH_1_HELM_RELEASE_NAMESPACE
    mesh1_log_and_execute helm uninstall $MESH_1_HELM_CTL_PLANE_RELEASE_NAME -n $MESH_1_HELM_RELEASE_NAMESPACE
    mesh1_log_and_execute oc delete project $MESH_1_ISTIO_CTL_PLANE_NS
    mesh1_log_and_execute oc delete project $MESH_1_BOOKINFO_NS

    mesh2_log "Uninstall Helm releases..."
    mesh2_log_and_execute helm uninstall $MESH_2_HELM_BOOKINFO_RELEASE_NAME -n $MESH_2_HELM_RELEASE_NAMESPACE
    mesh2_log_and_execute helm uninstall $MESH_2_HELM_CONNECTIVITY_RELEASE_NAME -n $MESH_2_HELM_RELEASE_NAMESPACE
    mesh2_log_and_execute helm uninstall $MESH_2_HELM_CTL_PLANE_RELEASE_NAME -n $MESH_2_HELM_RELEASE_NAMESPACE
    mesh2_log_and_execute oc delete project $MESH_2_ISTIO_CTL_PLANE_NS
    mesh2_log_and_execute oc delete project $MESH_2_BOOKINFO_NS
}

log() {
    TEXT_BOLD=$(tput bold)
    TEXT_NORMAL=$(tput sgr0)
    printf "${TEXT_BOLD}"
    echo $@
    printf "${TEXT_NORMAL}"
}

mesh1_log_and_execute() {
    mesh1_log "$@"
    mesh1_execute "$@"
    printf "\n"
}

mesh1_log() {
    log "For mesh1: $@"
}

mesh1_execute() {
    oc login --insecure-skip-tls-verify=true --token=$MESH_1_OCP_TOKEN --server=$MESH_1_OCP_SERVER_URL > /dev/null
    $@
}

mesh2_log_and_execute() {
    mesh2_log "$@"
    mesh2_execute "$@"
    printf "\n"
}

mesh2_log() {
    log "For mesh2: $@"
}

mesh2_execute() {
    oc login --insecure-skip-tls-verify=true --token=$MESH_2_OCP_TOKEN --server=$MESH_2_OCP_SERVER_URL > /dev/null
    $@
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