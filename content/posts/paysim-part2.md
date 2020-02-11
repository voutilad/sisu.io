+++
title = "Integrating PaySim with Neo4j (PaySim pt.2)"
author = ["Dave Voutila"]
description = "In which we look at how to leverage PaySim to build a fraud graph"
date = 2020-02-11
tags = ["neo4j", "fraud", "java", "paysim"]
draft = false
+++

[Previously]({{< relref "paysim" >}}), we looked at how PaySim models mobile money networks to
simulate hidden fraudulent behavior and how my fork[^fn:1] makes it
possible to build off the original authors' work.

In this post, we'll dive into the next step in building out demo:
connecting the running simulation to a live Neo4j instance.


## Prerequisites for you Home Gamers {#prerequisites-for-you-home-gamers}

If you plan to follow along, here's what you'll need:

-   JDK 8 or 11[^fn:2]
-   [Neo4j 3.5](https://neo4j.com/download) (community or enterprise)
-   Clone or download [paysim-demo](https://github.com/voutilad/paysim-demo)

The `paysim-demo` project uses a [gradle](https://gradle.org/) wrapper, so you shouldn't need
to install anything else.


## Designing the Integration {#designing-the-integration}

From last time, we've got an implementation of PaySim
that....TKTKTKTKTKTKT


### 1. Iteratively load PaySim Transactions {#1-dot-iteratively-load-paysim-transactions}


### 2. Label our Mules {#2-dot-label-our-mules}


### 3. Establish Identities and their Relationships {#3-dot-establish-identities-and-their-relationships}


### 4. Update additional Node Properties {#4-dot-update-additional-node-properties}


### 5. Thread Transactions into Chains {#5-dot-thread-transactions-into-chains}


## Tips for Bulk Loads using a Neo4j Driver {#tips-for-bulk-loads-using-a-neo4j-driver}

In this case, we're using the Java Driver, but the following applies
for any client-side data loading with Neo4j.

TKTKTKT

\*

[^fn:1]: <https://github.com/voutilad/paysim>
[^fn:2]: I recommend using an OpenJDK from <https://adoptopenjdk.net/>
