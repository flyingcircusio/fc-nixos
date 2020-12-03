.. _nixos2-kubernetes:

Kubernetes Cluster
==================

.. note::

    Kubernetes support is – at the moment – still experimental. Feel free
    to use it but we suggest contacting our support before putting anything into
    production. We only support the Kubernetes roles on our NixOS 20.09 platform.


Kubernetes Version and Documentation
------------------------------------

The current version is Kubernetes 1.19. Refer to the
`Kubernetes manual <https://v1-19.docs.kubernetes.io/docs/home/>`_.

Roles
-----

.. warning::
    The networks `10.0.0.0/24` and `10.1.0.0/16` will be used by Kubernetes for
    services and pods. They must not overlap with existing networks.
    Modify the defaults if needed before activating Kubernetes roles as
    described in :ref:`nixos2-changing-kubernetes-networks`!


By using our Kubernetes roles, you can set up a Kubernetes cluster for your
project automatically. We provide two roles:

The **kubernetes-master** role runs cluster management services and the Kubernetes API.
There must be exactly one VM per project with the master role.
Multi-master setups are not supported (yet).

VMs with the **kubernetes-node** role run pods that are assigned to them by the master.
There must be at least one node per project. Using at least 3 nodes is recommended.
Additional node VMs can be added at any time. They automatically register with the master.

The roles can be combined on a machine.

.. warning::

   Changing the master VM is not supported and requires substantial manual intervention.

Activating the node role on an existing master-only VM works,
but `taints <https://v1-19.docs.kubernetes.io/docs/concepts/configuration/taint-and-toleration>`_
must be disabled manually to run pods on it.


Cluster Management
------------------

**sudo-srv** users can run :command:`kubectl` on the master VM to manage the
cluster. You can also use the dashboard or :command:`kubectl` on your local
machine as described in :ref:`nixos2-dashboard-and-external-api`.

Basic Health Checks
^^^^^^^^^^^^^^^^^^^

Check that the master/API is working:

.. code-block:: console

    $ kubectl cluster-info

Check that the nodes are working:

.. code-block:: console

    $ kubectl get nodes

Check that Cluster DNS and dashboard pods are running:

.. code-block:: console

    $ kubectl get pods -n kube-system

This should show that 2 coredns pods and a dashboard pod are running.


.. _nixos2-dashboard-and-external-api:

External API Access
-------------------

**sudo-srv** users can generate a kubeconfig usable for :command:`kubectl`
by running :command:`kubernetes-make-kubeconfig`
on the VM with the master role. This kubeconfig contains all information needed
for access and can be copied to any machine.

.. warning::

  Protect kubeconfig files.
  They allow unrestricted access to the Kubernetes cluster!

Run:

.. code-block:: console

    $ kubernetes-make-kubeconfig > $USER-$HOST.kubeconfig

The kubeconfig contains the client certificate for the user and a
token to access a service account associated with the user.
Running the script for the first time sets up the service account.
Certificate and token provide **cluster-admin** privileges.
For authentication, Kubectl uses the SSL client certificate.

The API can be accessed from any machine using the kubeconfig:

.. code-block:: console

    $ export KUBECONFIG=./user-test.kubeconfig
    $ kubectl cluster-info

You can also move the kubeconfig to :file:`~/.kube/config` to use it as the
default config.

The certificate is valid for 365 days.
You must generate a new kubeconfig when the certificate expires.

Dashboard
---------

The Kubernetes dashboard can be accessed via `https://kubernetes.<project-name>.fcio.net`,
for example `https://kubernetes.myproject.fcio.net`.

The Kubernetes dashboard has full cluster admin privileges and is protected by HTTP basic auth.
Only users in the **login** group are allowed to log in.

After signing in with your FCIO credentials, a dashboard for a healthy cluster
should look like this:

.. image:: images/kubernetes_dashboard_healthy.png
   :width: 500px


Services: Accessing Applications Running on Kubernetes
------------------------------------------------------

A Service provides a way to access an application running on a set of pods
independent of the real location of the pods in the cluster.

Every Kubernetes node runs a `kube-proxy` that sets up iptables rules that allow
access of Kubernetes services via their **Service IP** (also called **Cluster IP**)
in the virtual service network. The default is *10.0.0.0/24*.

The `kube-proxy` provides load-balancing if there are multiple pods running behind a
a service.

Services can use fixed or floating IPs.
The dashboard uses *10.0.0.250* by default.
Service IPs can be resolved using the cluster DNS service:

.. code-block:: console

    $ dig @10.0.0.254 myapp.default.svc.cluster.local


where *myapp* is a service in the namespace *default*.

Other VMs in a project with a Kubernetes cluster can access services using a
Kubernetes node as router. A route for the service IP network is set up
automatically if Kubernetes nodes are found in the project.

Web applications running on the Kubernetes cluster should be
exposed to the public through frontend VMs using the :ref:`nixos2-webgateway`
role.
The easiest way to use a Kubernetes application as backend/upstream is to a
assign a fixed IP to the service and point to it in the Webgateway config.

For more information about Kubernetes services, refer to the
`Service chapter in the Kubernetes manual <https://v1-19.docs.kubernetes.io/docs/concepts/services-networking/>`_.


.. _nixos2-changing-kubernetes-networks:

Changing Kubernetes Networks
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. warning::

    These settings should only be changed before assigning Kubernetes roles.
    Changing them later requires manual intervention.

The service network which is *10.0.0.0/24* by default can be changed with the NixOS option
`services.kubernetes.apiserver.serviceClusterIpRange <https://nixos.org/nixos/options.html#services.kubernetes.apiserver.serviceclusteriprange>`_.
You also have to change `flyingcircus.roles.kubernetes.dashboardClusterIP` then.

The pod network which is *10.1.0.0/16* by default can be changed with the NixOS option
`services.kubernetes.clusterCidr <https://nixos.org/nixos/options.html#services.kubernetes.clusterCidr>`_.
