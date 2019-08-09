rhsso_project=sso
new_guid=`echo $HOSTNAME | cut -d'.' -f 1 | cut -d'-' -f 2`
stale_guid=`cat $HOME/guid`

enableLetsEncryptCertsOnRoutes() {
    oc new-project prod-letsencrypt
    oc create -f https://raw.githubusercontent.com/tnozicka/openshift-acme/master/deploy/letsencrypt-live/cluster-wide/{clusterrole,serviceaccount,imagestream,deployment}.yaml
    oc adm policy add-cluster-role-to-user openshift-acme -z openshift-acme

    # ERDemo Routes
    oc patch route/emergency-console --type=json -n emergency-response-demo \
         -p '[{"op": "add", "path": "/metadata/annotations/kubernetes.io~1tls-acme", "value":"true"}]'
    oc patch route/disaster-simulator --type=json -n emergency-response-demo \
         -p '[{"op": "add", "path": "/metadata/annotations/kubernetes.io~1tls-acme", "value":"true"}]'

    # SSO Route
    oc patch route/sso --type=json -n sso \
         -p '[{"op": "add", "path": "/metadata/annotations/kubernetes.io~1tls-acme", "value":"true"}]'
}




refreshStaleURLs() {
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
}

updateGUIDFile() {
    echo $new_guid > $HOME/guid
}

enableLetsEncryptCertsOnRoutes
refreshStaleURLs
updateGUIDFile
