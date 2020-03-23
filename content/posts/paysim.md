+++
title = "Simulating Mobile Money Fraud 🤑 (PaySim pt.1)"
author = ["Dave Voutila"]
description = "Creating a realistic data-set for analysis using PaySim"
date = 2020-02-13
lastmod = 2020-03-23T11:15:11-04:00
tags = ["neo4j", "fraud", "java", "paysim"]
draft = false
+++

<div class="ox-hugo-toc toc">
<div></div>

<div class="heading">Table of Contents</div>

- [Introduction](#introduction)
- [Background: A Mobile Money Primer 💸](#background-a-mobile-money-primer)
- [An Overview of PaySim](#an-overview-of-paysim)
    - [Agent Types](#agent-types)
    - [Transactions](#transactions)
    - [Step by Step (day by day?)](#step-by-step--day-by-day)
- [👷‍ Improving PaySim](#improving-paysim)
    - [⬆ Code Upgrades](#code-upgrades)
    - [Enhancing PaySim's Fraudsters](#enhancing-paysim-s-fraudsters)
- [Our Journey So Far](#our-journey-so-far)
- [Next Episode: Getting PaySim Transactions into Neo4j](#next-episode-getting-paysim-transactions-into-neo4j)

</div>
<!--endtoc-->



## Introduction {#introduction}

Fraud detection and investigation presents one of the most popular use
cases for graph databases, especially in the financial services
industry. But for those not employed directly by a bank or insurance
firm, it can be hard to study or experiment with realistic
data. If it's not obvious, _a lack of publicly available datasets is a
real problem for academics_ looking to develop machine learning or
heuristic approaches to fraud detection.

_Lopez-Rojas, Elmire, and Axelsson_[^fn:1] published **PaySim**, an
approach using an agent-based model and some anonymized, aggregate
transactional data from a real mobile money network operator to create
synthetic financial data sets academics and hackers can use for
exploring ways to detect fraudulent behavior.

> Check out their initial dataset posted to kaggle:
> <https://www.kaggle.com/ntnu-testimon/paysim1>

<a id="org92aecab"></a>

{{< figure src="/img/kaggle-arjunjoshua-paysim-fingerprints.png" caption="Figure 1: \"...fingerprints of [PaySim] transactions over time\" by Arjun Joshua" >}}

There've already been some good write-ups exploring the output of
PaySim, both in terms of the sample dataset posted to Kaggle circa 3
years ago and possible ML-based approaches to fraud detection like
those of Arjun Joshua[^fn:2]. Most recently, Sara Robinson[^fn:3],
[published an example](https://sararobinson.dev/2020/01/15/fraud-detection-tensorflow.html) using _TensorFlow_ and Google's _Cloud AI
Platform_ to build a predictive model.

But, what's the one thing all the ML-based approaches have in common?
**They all illustrate critical shortcomings in PaySim, specifically
its overly simplistic modeling of a single type of fraud.** They all
exploit the fact PaySim's logic for fraudsters is overly simplisitc.

Let's see if we can improve PaySim _and_ find new ways to identify
fraud using graphs with [neo4j](https://neo4j.com), shall we?

> This is the first post of a few (maybe 3?) that will explore my
> experimentation and research taking the open-source PaySim project,
> improving upon it, and integrating it with Neo4j to implement a fraud
> analytics platform.


## Background: A Mobile Money Primer 💸 {#background-a-mobile-money-primer}

To understand PaySim, we need to understand a little about what it was
built to model, specifically a _mobile money network._

Mobile money takes different forms, but in the case of PaySim it
involves both Banks and participating Merchants. Merchants can take
mobile payments via the network (for goods/services) as well as
perform the function of putting money into the network (e.g. "topping
up" an account).

If it sounds a lot like _Apple Pay_, it's because mobile payment
services are effectively a type of mobile money.

The mobile money network used by the PaySim authors comes from an
undisclosed African country, which leads me to believe it's of the
sort similar to [M-Pesa](https://en.wikipedia.org/wiki/M-Pesa).

From the M-Pesa Wikipedia page:

> M-Pesa is a branchless banking service; M-Pesa customers can deposit
> and withdraw money from a network of agents that includes airtime
> resellers and retail outlets acting as banking agents.

So consider it something like _Apple Pay_, but where you can also make
deposits via participating merchants.


## An Overview of PaySim {#an-overview-of-paysim}

If PaySim models financial transactions, what does it look like and
how does it work?

Let's jump a bit ahead and talk about what PaySim produces with the
help of a graph visualization and then dive into the core components
of the simulation: _Agents and Transactions._

<a id="orga757507"></a>

{{< figure src="/img/simplified-data-model.png" caption="Figure 2: Graphical representation of the PaySim data model" >}}

PaySim is a multiagent simulation, that steps through time, where
during each step the agents are allowed to act in ways that can change
themselves and the rest of the simulation state. If this sounds
confusing at first, PaySim functions with a single core axiom:

> `Clients` perform _zero or many_ `Transactions` at each step in time,
> exchanging money with other agents in the network, specifically
> `Banks`, `Merchants`, and other `Clients`.

Let's look a bit closer at both the types of Agents and the types of
Transactions that PaySim simulates.


### Agent Types {#agent-types}

Agents are the key actors, meaning they can perform actions in the
simulation. There are three (3) primary agent types and a few subtypes
as well.


#### 💳 Clients {#clients}

Clients model the end users in the mobile money network, effectively
mapping to unique accounts that, in theory, are controlled by real
people. Since Clients model people, and we're concerned about modeling
fraud, it follows that not all people in our simulation behave the
same way. (Surprise, surprise!)

-   Some clients are **Fraudsters** and manipulate the network and other
    clients to their own gain
-   Some clients act solely as **Mules**, a means of moving money around
    and ultimately out of the network
-   Most are clients just behave normally in how they conduct
    transactions, like good members of the community


#### 🏬 Merchants {#merchants}

Merchants model the vendors or businesses that participate in the
network through interactions with Clients.

-   Merchants act as a gateway to the network, allowing assets to flow
    into and out of the network
-   Merchants provide goods/services in exchange for money in the
    network like a traditional vendor


#### 🏦 Banks {#banks}

Banks are pretty inert in PaySim, acting only as a target for Debit
transactions. They appear to play a relatively limited role PaySim,
probably due to not being a critical component of the mobile money
network PaySim models. (Consider, for example, the point that some
mobile money networks exist in a market because its consituents are
"under banked.")

The only role Banks play is to facilitate _Debit_ transactions, which
seem more to be a debit against a client's balance in the network as
if they're transfering money back into their actual bank account.


### Transactions {#transactions}

Transactions form the cornerstone of PaySim that they're the only real
way client can interact with other agents. In fact, clients are the
only agents that perform transactions.

> While in the real world a financial transaction could occur initiated
> by banks, merchants, etc., PaySim focuses entirely on the behavior of
> the Clients.

What can a Client do each turn in the simulation? They have a choice
of five (5) possible transactions:

<a id="table--Transaction Types"></a>
<div class="table-caption">
  <span class="table-number"><a href="#table--Transaction Types">Table 1</a></span>:
  Table of Transaction Types
</div>

| Transaction | Description                                            |
|-------------|--------------------------------------------------------|
| CashIn      | A Client moves money into the network via a Merchant   |
| CashOut     | A Client moves money out of the network via a Merchant |
| Debit       | A Client moves money into a Bank                       |
| Transfer    | A Client sends money to another Client                 |
| Payment     | A Client exchanges money for something from a Merchant |

Depending on the type of transaction, certain rules apply:

-   Every transaction must have a second agent of a supported type,
    dependent on the type of transaction.

-   Only **Transfers** between clients require proper double-entry
    bookkeeping where there's a zero-sum. _(Corollary: the simulation's
    money supply can be increased/decreased via Merchants and Banks.)_

-   **Transfers** amounts must fall under a _global transfer limit_ set in
    the simulation parameters prior to simulation start. For larger
    transfers, they must be broken into multiple transactions.


### Step by Step (day by day?) {#step-by-step--day-by-day}

The last thing to note about PaySim (and then you'll be a PaySim
expert!), is that the simulation runs in discrete steps. At every
"step", each agent (in some deterministic order) gets an opportunity
to act.

In the case of PaySim:

-   Each "step" corresponds to **one (1) hour** of time
-   Agents, specifically Clients, may act **zero or many times** per step
-   Internal limitations cap PaySim at **720 steps** or **30 days** of
    simulated time[^fn:4]

From a code perspective, each agent in the simulation needs to
implement a simple `sim.engine.Steppable` interface[^fn:5] that the
simulation will call at each step while providing a reference to the
overall simulation state itself:

```java
/*
  Copyright 2006 by Sean Luke and George Mason University
  Licensed under the Academic Free License version 3.0
  See the file "LICENSE" for more information
*/

package sim.engine;

/** Something that can be stepped */

public interface Steppable extends java.io.Serializable
{
        public void step(SimState state);
}
```

In PaySim, all the [clients](#agent-types) implement `Steppable` and provide their own
logic for how they'll behave.


## 👷‍ Improving PaySim {#improving-paysim}

You can run PaySim as-is, out of the box, and generate synthetic data,
so why not just use it now to explore fraud and build our graph?
Well...it presents a few challenges:

1.  PaySim expects to write out simulation results as CSV files. While
    Neo4j natively supports loading csv[^fn:6], loading the transactions
    on the fly would open a lot more possibilities like simulating
    real-time detection and action.

2.  Transactions in PaySim contain only bare bones data, with some
    critical aspects left to be inferred.

3.  PaySim never explicitly documents all the actors in a simulation
    run, leaving you to infer their details from the raw transaction
    output. (In the code, however, it does keep track of all agents.)

Since PaySim is open source, I've forked the original and all the
changes we'll be walking through will be part of my PaySim 2.1.[^fn:7]

Before we dive in, the changes we want to make fall into two
categories:

-   improving ergnomics and usability of PaySim, allowing us to enhance
    it and add new features
-   expanding upon the modeling of Fraudsters, incorporating the two
    common types of fraudsters: 1st and 3rd party


### ⬆ Code Upgrades {#code-upgrades}

PaySim is provided as a Java application built upon the MASON agent
simulation framework[^fn:8], a mature and proven kitchen-sink
multi-agent simulation platform. However, the way PaySim was
implemented by the authors makes it challenging to build upon and
expand.

> Here I'll provide a high level overview of code improvements in my
> fork of PaySim available at <https://github.com/voutilad/paysim>.
>
> If you're not interested in some of the lower-level code changes, jump
> ahead to [Enhancing PaySim's Fraudsters](#enhancing-paysim-s-fraudsters).


#### Making PaySim more of a Library than an App {#making-paysim-more-of-a-library-than-an-app}

First up is fixing PaySim's desire to only output to the file
system. There are two primary improvements I made to make PaySim
embeddable as a library:

-   Abstracted out the base simulation logic from the orchestration, so
    the original PaySim can be run writing out to disk, but developers
    can implement alternative implementations doing whatever they want.

-   Implemented an iterating version of PaySim, allowing an application
    embedding PaySim to drive the simulation at its own pace and consume
    data on the fly.

The original PaySim logic is preserved, but the front-end is now
choosable by the developer or end-user. For example, to run something
analagous to the original PaySim project, you can run the `main()`
method in the `OriginalPaySim` class and it will write out all the
expected output files to disk.

<a id="org8c231f2"></a>

{{< figure src="/img/IteratingPaySim.svg" caption="Figure 3: IteratingPaySim Implementation (high-level)" >}}

If instead you want to drive the simulation using an implementation of
a Java `Iterator<org.paysim.base.Transaction>`, use the
`IteratingPaySim` class and consume transactions sequentially. A
worker thread drives the simulation in the background while data flows
via an buffered implementation of a `java.util.ArrayDeque`[^fn:9]. (The
nitty gritty details are beyond the scope of this post at the moment.)


#### Improving PaySim Transactions & History {#improving-paysim-transactions-and-history}

This part is a relatively simple change as to keep compatibility with
the original PaySim logic I've kept the `Transaction` implementation
relatively the same, with the key exception of adding in details about
the actor "types" on the sending and receiving end.

Since all actors derive from the `org.paysim.actors.SuperActor` base
class, they all implement some _getter_ for a `SuperActor.Type`
value (an enum).

By tracking the `SuperActor.Type` on the `Transaction`:

1.  We don't have to keep references to the actors and they can
    ultimately be garbage collected by the JVM if we destroy the
    simulation.

2.  More importantly, we can always know what type of actors the
    transaction pertains to, allowing us to accurately look up specific
    instances either in PaySim's tracking of Clients/Merchants/Banks or
    in our resulting database.


#### Other Miscelanneous Housekeeping {#other-miscelanneous-housekeeping}

I made various touchups and tweaks that are too in-the-weeds for this
blog post, so if you're interested make sure to check out the
project's [README](https://github.com/voutilad/PaySim#why-fork) for some more details. Some items of note:

-   removed reliance on Java `static` members allowing multiple
    configurations of PaySim to be loaded
-   reduced MASON's footprint, removing uneeded features
-   incorporated [SL4j](http://www.slf4j.org/) logging framework, removing reliance on
    `System.out` for logging


### Enhancing PaySim's Fraudsters {#enhancing-paysim-s-fraudsters}

With the foundation improved, we can now work on shoring up the logic
for our fraudsters. Let's first look at how the original PaySim
fraudsters behave and then get into the changes for 1st and 3rd Party
implementations.


#### 😏 The Original PaySim Fraudster Behavior {#the-original-paysim-fraudster-behavior}

PaySim originally only models what looks to be a form of 3rd-party
fraud:

1.  Fraudsters target an established Client account (the victim)
2.  Fraudsters trigger Transfers from that victim to a Mule account the
    Fraudster creates
3.  When the Mule has a certain balance level it performs a `CashOut`

A real-world example of this might be someone breaching someone's
mobile money account via credential skimming/theft or phishing. Once
the Fraudster has access to the payment card they can cash out by
buying gift cards or prepaid cards that can in turn either be used or
sold to convert to actual cash.

**Can we make it a tad more realistic?**

-   Fraudsters try to completely drain a Victim's account, performing
    Transfers up to the network "transfer limit" set by the model
    parameters.
    -   In real world credit card fraud, cards are usually "tested"
        through small transactions or pre-authorization before being used
        for big purchases.

-   A PaySim Fraudster picks a Victim from the simulation universe at
    random.
    -   In the real world, while there's some behavior that may appear
        random, Fraudsters often breach or compromise a Merchant's POS
        systems (both offline and online) to initially gain access to
        victims' accounts.

With the above in mind, let's first talk about turning our generic
PaySim fraudster into a **3rd Party Fraudster.**


#### Improving 3rd Party Fraudsters {#improving-3rd-party-fraudsters}

We'll enhance our 3rd-party Fraudsters to incorporate a few new
behaviors bringing it closer to realistic behavior:

-   To simulate merchant breaches, card skimming, etc., support storing
    "favored" Merchants that the Fraudster will use as a means of
    targeting Clients for victimization
-   Keep track of fraud victims, the easiest target of future fraud
-   For new Victims, try making "test charges" simulating real world
    card testing[^fn:10]

Like the original PaySim, we'll keep the idea that a 3rd-party
Fraudster creates a Mule account as a means of cashing out of the
network.

For logic changes, let's keep it simple but accounting for some key
events:

1.  Test fraud probability like in original PaySim. If test fails,
    abort actions for this simulation step.

2.  If there are no victims _OR_ we pass a probability check for
    picking a new victim, we enter New Victim mode:
    -   Pick a Merchant at random from favored merchants.
    -   Pick a Client via the Merchant history at random _OR_ if there is
        no favorted Merchant, pick a random Client from the universe.
    -   Conduct "Payment" transcations acting as test charges
    -   If the test charge succeeds (i.e. Victim has non-zero balance),
        then try performing a "Transfer" of some percentage of the Client
        balance to a Mule.

3.  Otherwise, pick an existing Victim at random and try a "Transfer"
    of some percentage of the Client balance to a Mule.

> See [ThirdPartyFraudster.java](https://github.com/voutilad/PaySim/blob/master/src/main/java/org/paysim/actors/ThirdPartyFraudster.java) in the code base for implementation
> details.


#### 🎭 1st Party (Synthetic) Fraudsters {#1st-party--synthetic--fraudsters}

First Party Fraud typically entails misrepresenting oneself in order
to establish a line of credit with no intent to fulfill any
debts. (See the definition in [Open Risk Manual](https://www.openriskmanual.org/wiki/First%5FParty%5FFraud).)

A more interesting form of fraud is [synthetic identity fraud](https://www.datavisor.com/wiki/synthetic-identity-theft/) where
instead of using their own identifying information, fraudsters mix
real with fake identifiers in order to slip past fraud checks when
opening accounts or getting credit lines.

Should be easy to add to PaySim, _but PaySim doesn't have any form of
identities!_

First, we'll have to bend our definition of the payment network being
modeled by PaySim and assume some of it involves lines of credit.

Next, adding identities is pretty easy, but requires a bit of an
overhaul across the agent (actor) codebase: we ultimately needs all
Clients, whether Fraudsters, Mules, or regular, to have some
identifiable details that are generally unique.


#### Modeling Identities {#modeling-identities}

What should it look like in the end? From a graph perspective, there's
a pretty trivial way to incorporate identities with Clients: relate
each Client to an instance of an Identity.

<a id="orgb5e173b"></a>

{{< figure src="/img/simple-identity-model.png" caption="Figure 4: Pretty simple model: Client's have one or many identifiers" >}}

From the PaySim code perspective, it gets a bit trickier, and easily
can turn into a [bike shedding](https://en.wikipedia.org/wiki/Law%5Fof%5Ftriviality) exercise. Here's where I ended up:

-   All `SuperActor` instances (our base actor class) are
    `Identifiable`.
    -   Being `Identifiable` means you have an "Id" and a "Name" (both
        Strings) as attributes.
    -   It also means you can provide a reference to an `Identity`.

-   An `Identity` effectively is a container for the different identity
    attributes (name, id, etc.) and there are multiple implementations:
    -   A `BankIdentity` and `MerchantIdentity` both only have an "Id" and
        a "Name".
    -   A `ClientIdentity` is more representitive of a "person", having
        not only a "Name" and "Id", but others like "email", "ssn", and
        "phone" numbers.

-   An `IdentityFactory` provides a deterministic means of producing
    "random" identities as needed.
    -   It effectively abstracts a 3rd party library ([jFairy](https://github.com/Devskiller/jfairy)) I'm
        currently using to generate "realistic" people and companies.
    -   While jFairy uses a different random number generator than the
        core of PaySim, it can take a seed and produce deterministic
        results, which is key to keeping PaySim reproducable.

-   Constructors for actors get overhauled to optionally take a
    reference to an `Identity` implementation _OR_ will generate one if
    not provided.

_PHEW!_ If you want to look at the code mess, the [org.paysim.identity](https://github.com/voutilad/PaySim/blob/master/src/main/java/org/paysim/identity/)
package contains most of the additional code. Also check out some
commits like [78b1cfb](https://github.com/voutilad/PaySim/commit/78b1cfba74d3291bdcc90dfc332b2b28a2abc3f4) and [f7b174a](https://github.com/voutilad/PaySim/commit/f7b174a698d7fdd3f49b61255944975b05339146) to see how things were changed.


#### Building the 1st Party Fraudster {#building-the-1st-party-fraudster}

Now that we have an identity component to our actors, let's put
together a new fraudster.

Using security breaches and identity theft stories from the headlines,
let's pretend our fraudster acquired some number of viable identities
(names, ssn's, and phone numbers). When we create a 1st-party
fraudster, we can generate a handful of identities and give them to
the fraudster.

For committing the fraud, we'll start with a pretty trivial
implementation:

1.  Do a fraud probability check to see if we continue or skip running
    during this simulation step.
2.  Generate a "new" identity, composing parts from our "stolen"
    identities.
3.  Create the new client account using the identity.
4.  Drain whatever starting balance was given to the new account,
    transferring its balance to the fraudster's designated Mule.
5.  Profit.

From a Java implementation standpoint[^fn:11], it's pretty short and
sweet:

```java
@Override
public void step(SimState state) {
    PaySimState paysim = (PaySimState) state;
    final int step = (int) state.schedule.getSteps();

    if (paysim.getRNG().nextDouble() < parameters.fraudProbability) {
        ClientIdentity fauxIdentity = composeNewIdentity(paysim);
        Mule m = new Mule(paysim, fauxIdentity);

        Transaction drain = m.handleTransfer(cashoutMule, step, m.balance);
        fauxAccounts.add(m);
        paysim.addClient(m);
        paysim.onTransactions(Arrays.asList(drain));
    }
}
```

<aside>
  <aside></aside>

You'll probably notice the use of a `Mule` instead of `Client`. This
is because a `Mule` effectively is a "brain dead" `Client` that
doesn't try to perform regular transactions each step. This prevents
the fraudulent account from running amock.

</aside>


## Our Journey So Far {#our-journey-so-far}

At this point, we've got a revamped, new version of PaySim that can be
run standalone or embedded. We've also got an understanding of our
data model and how we plan on adapting it to our graph model, laying
the foundation. Our data model is also slightly different.

<a id="org146f78e"></a>

{{< figure src="/img/paysim-2.1.0-part1.png" caption="Figure 5: Our Updated PaySim 2.1 Data Model" >}}

You'll notice that unlike [what we started with](#orga757507), it now provides
identifiers (e.g. `Phone`, `Email`, `SSN`) for each Client account
(which may or may not be a Mule).

Other enhancements in PaySim 2.1 not visible in the data model:

-   Fraudsters now come in two flavors: 1st and 3rd Party
    -   1st Party now use identifiers to create clients they control
    -   3rd Party now attack clients via merchant connections
-   Clients become more exposed to fraud risk if they conduct
    transactions with targeted merchants

To me this feels like an improvement. Let's now put it to work and
simulate some fraud!


## Next Episode: Getting PaySim Transactions into Neo4j {#next-episode-getting-paysim-transactions-into-neo4j}

In my [next post]({{< relref "paysim-part2" >}}), we'll look at how to configure and run a PaySim
simulation while simultaneously bulk loading the transaction output
into a live Neo4j instance. We'll cover:

-   Leveraging the Neo4j _Java Driver_[^fn:12] to load PaySim Transactions
    on-the-fly as the simulation runs
-   Best practices for batch/bulk data loading to get high throughput on
    database writes
-   How to threading transactions into _event chains_ and why that's
    helpful for downline analysis

A final post (TBA) will dive into how to analyze the data from both a
visual perspective as well as an algorithmic approach using Neo4j's
Graph Algorithms library.

_Until next time! 👋_

[^fn:1]: [PaySim:A Financial Mobile Money Simulator For Fraud Detection](https://www.researchgate.net/publication/313138956%5FPAYSIM%5FA%5FFINANCIAL%5FMOBILE%5FMONEY%5FSIMULATOR%5FFOR%5FFRAUD%5FDETECTION)
[^fn:2]: See Arjun's Kaggle notebook here: <https://www.kaggle.com/arjunjoshua/predicting-fraud-in-financial-payment-services>
[^fn:3]: Sara is a Developer Advocate for Google Cloud. You can find her blog at <https://sararobinson.dev/>
[^fn:4]: This is due to PaySim using aggregate data to drive the simulation and the data provided (by the original authors) only covers 30 days. Modifying this data will allow PaySim to produce different outcomes of differing lengths.
[^fn:5]: <https://github.com/voutilad/mason/blob/728bdc43f35dd52c06ffce99a704f3191c2fcfa4/mason/src/main/java/sim/engine/Steppable.java>
[^fn:6]: <https://neo4j.com/developer/guide-import-csv/>
[^fn:7]: As such, PaySim is provided under the GPLv3 and my fork is available at <https://github.com/voutilad/PaySim>.
[^fn:8]: See the MASON project's home page: <https://cs.gmu.edu/~eclab/projects/mason/>
[^fn:9]: <https://docs.oracle.com/javase/8/docs/api/java/util/ArrayDeque.html>
[^fn:10]: See Stripe's docs on how they define "card testing" <https://stripe.com/docs/card-testing>
[^fn:11]: <https://github.com/voutilad/PaySim/blob/3cfb56d0d52e45157f387144e8a4d0be7bcb7850/src/main/java/org/paysim/actors/FirstPartyFraudster.java#L44>
[^fn:12]: <https://github.com/neo4j/neo4j-java-driver>
