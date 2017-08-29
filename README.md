# ec2-ipam

A docker ipam driver for ipvlan networks on ec2

## Notes about coffeescript

The code itself is written in [coffee-script2](http://coffeescript.org/v2).
you can have it installed by `npm install coffeescript@next`, or you may use the
Dockerfile provided

## Installing

You will need to add a subnet to your VPC and add ENIs to your instances,
I will take eth1 as a example.

Using eth0 is possible but not recommended.

You should bring the interface up but no need to assign addresses, add this to
your `/etc/network/interfaces` will do the trick:

```
auto eth1
iface eth1 inet manual
  up ifconfig eth1 up
  down ifconfig eth1 down
```

Then make a copy of `ec2-ipam.json` to `/etc/docker/plugins`, remember to change
the url if you're not doing it on localhost.

You can use one ipam server for many clients.

The server would require a MySQL database for tracking address allocation, typically
a RDS instance will work. You should create the table with this scheme:

```
CREATE TABLE `allocation` (
  `ip` varchar(32) NOT NULL,
  `subnet` varchar(32) NOT NULL,
  `status` enum('free','ready','allocated','occupied','reserved') NOT NULL DEFAULT 'free',
  `iface` varchar(32) DEFAULT NULL,
  `primary` tinyint(1) NOT NULL,
  `ts` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `allocation`
  ADD PRIMARY KEY (`ip`),
  ADD KEY `free` (`subnet`,`status`) USING BTREE;
```

Then update config.json for database connection details.

You need to initialize the database with `bin/init.coffee`, this will scan your subnet
and find free addresses to fill the table. you only need to do this once per subnet.

At last, pull the trigger with `main.coffee` and you are all set.

You can have the docker network created by running `mknet.sh` on your instances.
you only need to run it once as long as you don't delete the network.

## Multi-tenancy

You can have multi ENIs installed to your ec2 as much as AWS allows you to do.
and you could have these ENIs isolated by enforcing subnet access lists.
