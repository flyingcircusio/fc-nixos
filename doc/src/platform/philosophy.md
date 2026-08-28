---
global_sync_id: "v1"
---

# Philosophy

The Flying Circus is a managed, agile platform for hosting Python web
applications.

We provide virtual Linux machines enabling developers to use any software they
like in an environment they know but without having to administer an operating
system.

We provide widely-used open-source web application components like nginx,
haproxy, varnish, PostgreSQL, and more. All of them are managed with a
production-proven configuration but you also have the freedom to adjust their
configuration to your needs.

All of the Flying Circus is managed: we take care of all the operational issues
like monitoring, installing updates and patches, backup, user management, etc.
so that you can focus on building your application and take care of your
customers.

Also, we love every single VM and make sure it is healthy and is performing
well at any time.

## Our approach

Our approach to the Flying Circus is based on a set of principles, methods, and
practices sometimes referred to as [DevOps](https://secure.wikimedia.org/wikipedia/en/wiki/DevOps).

To us, the most important aspects are:

Automation

: We automate almost everything: from provisioning physical or virtual
  machines, to installing packages together with their monitoring
  configuration, to complete operating system updates.

  This speeds up the initial configuration and helps keeping your
  configuration up-to-date even if your application has been running for
  months or years.

  It also ensures that you profit from new features and bug fixes without
  having to buy new stuff or hiring us to configure it.

  However, if you need something quick, we'll make sure that the automation
  does not get in your way and will figure something out for you.

Virtualisation

: Hardware is expensive, dirty, unreliable, and inflexible. That is why we
  provide you with virtual machines instead: many things become cheap,
  clean, reliable and flexible.

  We take care of all the complicated things related to
  hardware and in return you get all the good things from virtualised environments:

  - allocating the resources (CPU power, disk, memory) that you actually need
    and only paying for what you use
  - adjusting the allocated resources in a timely manner usually in a few
    minutes or hours
  - isolating services in  separate machines increases reliability,
    cleanliness, and flexibility
  - hardware failures become irrelevant, hardware improvements become
    available without reinstalling the system

Continuous improvements

: When operating a web application today, chances are that you are already
  continuously improving it.

  However, if a server is set up once it will get old and the time will come
  when your application can not evolve any longer in that crufty, old setup.

  We continuously keep both your virtual machines and our configurations
  up to date and introduce new features and technology so that your
  application will always find a modern, secure environment to work in.

  In our heavily automated environment we express almost all of our
  infrastructure as programming code and thus can leverage similar tools
  that you know from developing your application:

  - checking everything into revision control
  - making heavy use of testing and quality assurance before rolling
    anything out into production
  - being able to revert back to or take a look at previous releases
  - providing change logs

  Also, we'd like to hear from you about what you are missing or what you
  dream of - there is a good chance that we can help building that.

Monitoring

: Something that works today may not work tomorrow.

  As any application today consists of many parts working together
  seamlessly nobody can personally keep track of the status of the overall
  system.

  We therefore monitor many parameters of all systems and applications and
  keep you informed of their current status as well as giving you accesss to
  the historic data about their availability and their performance.

  In addition to the automatically deployed system checks your application
  can be monitored closely given that you provide the necessary information
  to us.

Security

: Running your application with a service provider implies that your data
  (and the data of your customers) is stored at a location that you do not
  have direct access to.

  To keep your data secure we adhere to industry standard practices as well
  as Germany's laws about privacy and data protection (one of the most
  strict laws on this issue in the world).

  Specifically this means:

  - employing both technical and organisational measures
  - applying security patches timely
  - selecting appropriate data centers
  - [documenting our approach closely](../security/index.md)

% XXX
%
% Open source
%     umfassende features, viel wissen bei uns, niedrige kosten durch open-source
%
% Commodity components
%     niedrige kosten durch standardisierte, commodity hardware, hohen
%
% Small team of specialists
%     kleines team

## Our tools

Our platform runs on top of Linux with [KVM](http://www.linux-kvm.org) virtual
machines and uses a structured approach to automated systems management and
operation with [NixOS](https://nixos.org).

A detailed list of used hardware and software can be provided on request.

% XXX talk about
%
% hardware
%
% storage
%
% details zum rechenzentrum
%
% ip connectivity
%
% netzwerk

## Our offers

For details about our commercial offerings based on the Flying Circus hosting
infrastructure, please visit our [homepage](https://flyingcircus.io).
