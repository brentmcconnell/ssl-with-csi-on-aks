* Start with basic AKS public cluster provided by this Terraform repo.  Change terraform.tfvars and variables.tf before running to suit your needs.  This requires an existing resource group be provided.
* After running the Terraform above to completion continue with the following steps...
* Upload cert with “az keyvault certificate import --vault-name NAME_OF_KEYVAULT -n NAME_OF_CERT_IN_KV -f CERTIFICATE.PFX”
* Pull AKS credential to local environment with “az aks get-credentials -n AKS_CLUSTER_NAME -g AKS_RG_NAME”
* Verify you can see AKS cluster resources with “kubectl get nodes” from your local command line tool
* Install NGINX via helm chart using:
```
helm install ingress-nginx ingress-nginx/ingress-nginx \
--namespace ingress-basic —create-namespace\
--set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz \
--set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-resource-group"="RG-NAME” \
--set controller.service.loadBalancerIP=“IP_ADDRESS”
```
* Execute “kubectl get services -A”.  You should see ingress-nginx-controller as a service with an EXTERNAL-IP if this does not have an IP address or says <pending> there is a problem.  The IP address you provided above should be the EXTERNAL-IP.
* Verify you see “aks-secrets-store-csi-driver-xxxx” and “aks-secrets-store-provider-azure-xxxxx” running using “kubectl get pods -A”.  You should see one pod for each of these services for each node in the cluster.
* Modify the secretprovider.yaml file from the repo and change the following
    * “objectName” field to the name you used for your certificate in Step #2.
    * “tenantId” to your organization’s tenant
    * “userAssignedIdentityID” to the secret provider’s managed identity.  This can be obtained by running the following “az aks show -g RG-NAME -n AKS_CLUSTER_NAME —query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv”.  NOTE:  useVMManagedIdentity should be “true” and objectType should be “secret”
* If you used the provided yaml to create the secret store you should now have a secret store named “azure-tls”.  You can verify this by executing “kubectl apply -f busybox.yaml” using the busybox.yaml file from the GH repo.  Once the pod is running you can execute “kubectl exec busybox-secrets-store-inline -- ls /mnt/secrets-store/“.  You should see the object you created in the KeyVault with the name you provided Step #6.
* You should also be able to see a secret named “ingress-tls-csi” if you execute “kubectl get secrets -A”
* At this point you can create your application deployment and service in AKS.  For this example I’ve used a simple publicly available container.  Execute “kubectl apply -f aks-helloworld-one.yaml”.  This only works if you did not change the secret store name from Step #6 since it relies on a secretproviderclass names “azure-tls”
* At this point you should have a running container but no ingress yet.  Verify the container is running using “kubectl get pods -A”.  You should see a pod called “aks-helloworld-one-xxxxx-xxxxx”.
* Next setup ingress for this service by running “kubectl apply -f aks-helloworld-one-ingress.yaml”.
* At this point you should be able to hit your address from DNS in a browser to see a basic webpage that says “Welcome to Azure Kubernetes Service”
