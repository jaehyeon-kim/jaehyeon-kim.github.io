---
layout: post
title: "2015-11-28-Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server"
description: ""
category: R
tags: [programming]
---
I mainly use Windows but need to work on Linux for development. One way to use Linux on my Windows machine is using [VirtualBox](https://www.virtualbox.org/). I used to have CentOS destop distribution but it was too much as I didn't need most of its desktop features. A Linux server is good for this purpose but it was quite out of hand until I found out a guest machine can be connected via SSH and RStudio Server. In this post, a quick way to connect to a Ubuntu guest via SSH using [Putty](http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html) and RStudio Server is illustrated. Also a way to transfer a file between the machines using [WinSCP](http://winscp.net/eng/index.php) is demonstrated.

#### SSH

Once a VM is installed, it is necessary to set up two network adapters: Bridged Adapter and Host-only Adapter. My setup is shown below. (See further details [here](https://www.ulyaoth.net/resources/tutorial-ssh-into-a-virtualbox-linux-guest-from-your-host.35/).)

![center](/figs/2015-11-28-Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server/vm_network.png)

Then [OpenSSH Server](https://help.ubuntu.com/lts/serverguide/openssh-server.html) should be installed in the guest machine and connection via _port 22_ should be allowed - it is the default SSH port. This job can easily be done as following.

{% highlight r %}
sudo apt-get update

sudo apt-get install openssh-server

sudo ufw allow 22
{% endhighlight %}

The ip address of the guest can be checked by `ip addr` and it can be used to set up a session in Putty (`user-name@ip-address`).

![center](/figs/2015-11-28-Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server/ip_addr.png)

Setting up a Putty session is as simple as the following.

![center](/figs/2015-11-28-Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server/putty.png)

Once the above steps work well, it is possible to connect to the guest via SSH.

![center](/figs/2015-11-28-Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server/putty_terminal.png)

#### WinSCP

Transferring a file to and from a guest can be done easily using WinSCP. The session login window is quite intuitive and mine is shown below.

![center](/figs/2015-11-28-Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server/winscp.png)

Once logged on, a file can be dragged and dropped between the machines.

![center](/figs/2015-11-28-Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server/winscp_transfer.png)

#### RStudio Server

Putty Terminal may or may not be good to work on and it may be not if R is used interactively. In this case, RStudio server can be a good option.

As the lastest version of R is not included in Ubuntu LTS, it is good to install the latest version as recommended in the [download page](https://www.rstudio.com/products/rstudio/download-server/). I added the following line in `/etc/apt/sources.list`.

{% highlight r %}
deb https://<my.favorite.cran.mirror>/bin/linux/ubuntu trusty/
{% endhighlight %}

When I tried to update the package by `sudo apt-get update`, however, _GPG error_  was encountered, indicating *NO_PUBKEY 51716619E084DAB9*. After some search, I was able to resolve it by the following. (See [this](http://ubuntuforums.org/showthread.php?t=1869890))

{% highlight r %}
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 51716619E084DAB9

sudo apt-get update
{% endhighlight %}

Then I was able to install R and the development packages.

{% highlight r %}
sudo apt-get install r-base

sudo apt-get install r-base-dev
{% endhighlight %}

If you need to install a package that requires *curl* and *xml* libraries (eg *devtools*), they should be installed.

{% highlight r %}
sudo apt-get install libcurl4-openssl-dev libxml2-dev
{% endhighlight %}

Then Rstudio Server can be connected via a browser of the host machine. Type *guest-ip-address:8787* in the address bar. The guest machine's user name and password can be used to log on. Mine is shown below.

![center](/figs/2015-11-28-Connecting-to-VirtualBox-Guest-via-SSH-And-RStudio-Server/rstudio.png)
