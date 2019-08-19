rhsso_project=sso

setUserPermissions() {
    oc adm policy add-role-to-user admin user1 -n emergency-response-demo
    oc adm policy add-role-to-user admin user1 -n emergency-response-monitoring
    oc adm policy add-role-to-user admin user1 -n tools-erd
}

enableLetsEncryptCertsOnRoutes() {
    oc delete project prod-letsencrypt
    oc new-project prod-letsencrypt
    oc create -fhttps://raw.githubusercontent.com/gpe-mw-training/openshift-acme/master/deploy/letsencrypt-live/cluster-wide/{clusterrole,serviceaccount,imagestream,deployment}.yaml -n prod-letsencrypt
    oc adm policy add-cluster-role-to-user openshift-acme -z openshift-acme -n prod-letsencrypt

    echo -en "metadata:\n  annotations:\n    kubernetes.io/tls-acme: \"true\"" > /tmp/route-tls-patch.yml
    oc patch route emergency-console --type merge --patch "$(cat /tmp/route-tls-patch.yml)" -n emergency-response-demo
    oc patch route disaster-simulator --type merge --patch "$(cat /tmp/route-tls-patch.yml)" -n emergency-response-demo
    oc patch route responder-simulator --type merge --patch "$(cat /tmp/route-tls-patch.yml)" -n emergency-response-demo
    oc patch route sso --type merge --patch "$(cat /tmp/route-tls-patch.yml)" -n $rhsso_project
}




refreshStaleURLs() {
    new_guid=`echo $HOSTNAME | cut -d'.' -f 1 | cut -d'-' -f 2`
    stale_guid=`cat $HOME/guid`

    # Switch to namespace of RHSSO
    oc project $rhsso_project

    echo -en "\nwill update the following stale guid in RHSSO from: $stale_guid to $new_guid\n\n"

    # update redirect_uris
    oc exec `oc get pod | grep "sso-postgresql" | awk '{print $1}'` \
        -- bash -c \
        "psql root -c \"update redirect_uris set value = replace(value, '$stale_guid', '$new_guid' ) where value like '%$stale_guid%';\""

    # update redirect_uris
    oc exec `oc get pod | grep "sso-postgresql" | awk '{print $1}'` \
        -- bash -c \
        "psql root -c \"update web_origins set value = replace(value, '$stale_guid', '$new_guid' ) where value like '%$stale_guid%';\""


    echo -en "\n\nupdated URLs in web_origins and redirect_urs .... \n"
    oc exec `oc get pod | grep "sso-postgresql" | awk '{print $1}'` \
        -- bash -c "psql root -c \"select client_id, value from redirect_uris where value like '%$new_guid%'\""

    echo -en "\n\n"

    oc rollout latest dc/sso -n $rhsso_project

    oc patch cm/sso-config --patch '{"data":{"AUTH_URL":"https://sso-sso.apps-'$new_guid'.generic.opentlc.com/auth"}}' -n emergency-response-demo
    oc rollout latest dc/emergency-console -n emergency-response-demo

    echo $new_guid > $HOME/guid
}

setUserPermissions
enableLetsEncryptCertsOnRoutes
refreshStaleURLs
