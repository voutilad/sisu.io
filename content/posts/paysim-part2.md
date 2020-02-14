+++
title = "Integrating PaySim with Neo4j 🔌 (PaySim pt.2)"
author = ["Dave Voutila"]
description = "In which we look at how to leverage PaySim to build a fraud graph"
date = 2020-02-13
lastmod = 2020-02-14T12:13:55-05:00
tags = ["neo4j", "fraud", "java", "paysim"]
draft = false
+++

<div class="ox-hugo-toc toc">
<div></div>

<div class="heading">Table of Contents</div>

- [Prerequisites for you Home Gamers](#prerequisites-for-you-home-gamers)
- [Starting with the End in Mind](#starting-with-the-end-in-mind)
- [Time to Write Some Code!](#time-to-write-some-code)
- [Putting it All Together](#putting-it-all-together)
- [Let's Run It! 🏃](#let-s-run-it)
- [Wrapping Up](#wrapping-up)
- [Next Time: Analyzing our Graph](#next-time-analyzing-our-graph)

</div>
<!--endtoc-->

[Previously]({{< relref "paysim" >}}), we looked at how PaySim models mobile money networks to
simulate hidden fraudulent behavior and how my fork[^fn:1] makes it
possible to build off the original authors' work and model more
realistic fraud cases.

In this post, we'll put PaySim 2.1 to work and integrate it to Neo4j's
graph database.

> NOTE: Throughout this post, I'll refer to my fork of PaySim as just
> "PaySim" to avoid having to constantly distinguish it as "PaySim 2.1"
> or something similar.


## Prerequisites for you Home Gamers {#prerequisites-for-you-home-gamers}

If you plan to follow along, here's what you'll need on your local
workstation:

-   JDK 8 or 11[^fn:2]
-   [Neo4j v3.5](https://neo4j.com/download) (community or enterprise)
-   Clone or download the [paysim-demo](https://github.com/voutilad/paysim-demo) project

The `paysim-demo` project uses a [gradle](https://gradle.org/) wrapper, so you shouldn't need
to install anything else assuming it can find your local Java
installation provided by the JDK.

> If you're new to Neo4j, I recommend grabbing a copy of [Neo4j Desktop](https://neo4j.com/download)
> to make it easier to get started. Check out the online [guide](https://neo4j.com/developer/neo4j-desktop/) and
> configure a new project to follow along.


## Starting with the End in Mind {#starting-with-the-end-in-mind}

Ultimately, we want to populate a graph in Neo4j, but our graph should
facilitate a few types of data exploration we'll want to perform to
test our fruad detection approaches:

-   We'll want to easily know which Clients are actually Mules and
    working on behalf of fraudsters. (This is important since Fraudsters
    act as invisible hands in the network.)
-   We need to relate identities to Clients so we can detect identity
    reuse.
-   We want to easily see a timeline of a Client's behavior in terms of
    their Transactions, so we want an easy to follow traversal path or
    chain.

Everything except the chaining was visible in our [previous data
model]({{< relref "paysim" >}}), so here's how it should look when we're done:

<a id="org2b7728c"></a>

{{< figure src="/img/paysim-2.1.0.png" caption="Figure 1: Our target PaySim 2.1 data model" >}}

You'll notice to support event chaining that there are now additional
relationships between Clients and Transactions along with Transactions
to other Transactions. We'll get into details as to how/why later in
this post.


## Time to Write Some Code! {#time-to-write-some-code}

We're going to dive into the weeds a bit around implementing a simple
Java app that will drive PaySim and feed data to Neo4j. Feel free to
skim the code parts and focus on just the logic/overviews if Java
isn't your "cup of tea." 😉 For you JavaScript folks, I tend to use
Java 8's newer closure/stream/etc. capabilities meaning it'll read
closer to something you may recognize, so try <span class="underline">not</span> to skip ahead!

> I recommend having some familiarity with the workings of the Neo4j
> Java Driver, so take a moment and check out the the latest manual
> available at <https://neo4j.com/docs/driver-manual/4.0/>.

We'll walk through six (6) steps to populate our graph:

1.  [Schema creation](#step-1-enforcing-a-schema)
2.  Iteratively load PaySim transactions
3.  Disguising the Mules
4.  Loading identities
5.  Updating any additional properties
6.  Threading transactions into event chains

We'll look at each step in isolation and then I'll show you how it can
be all put together.


### Step 1: Enforcing a Schema {#step-1-enforcing-a-schema}

Neo4j is a database and while closer to a NoSQL database than an
RDBMS, like any database it performs better if you can describe a bit
about the constraints of your system.

In our case, we know some facts about how PaySim models behavior,
specifically the uniqueness properties of agents, identifiers, and
transactions. Let's make some basic uniqueness assertions using
Cypher's `CREATE CONSTRAINT ON` clauses.

```cypher
// Core Types
CREATE CONSTRAINT ON (c:Client) ASSERT c.id IS UNIQUE;
CREATE CONSTRAINT ON (b:Bank) ASSERT b.id IS UNIQUE;
CREATE CONSTRAINT ON (m:Merchant) ASSERT m.id IS UNIQUE;
CREATE CONSTRAINT ON (m:Mule) ASSERT m.id IS UNIQUE";

// Transaction Types
CREATE CONSTRAINT ON (tx:Transaction) ASSERT tx.id IS UNIQUE;
CREATE CONSTRAINT ON (c:CashIn) ASSERT c.id IS UNIQUE;
CREATE CONSTRAINT ON (c:CashOut) ASSERT c.id IS UNIQUE;
CREATE CONSTRAINT ON (d:Debit) ASSERT d.id IS UNIQUE;
CREATE CONSTRAINT ON (p:Payment) ASSERT p.id IS UNIQUE;
CREATE CONSTRAINT ON (t:Transfer) ASSERT t.id IS UNIQUE;

// Identity Types
CREATE CONSTRAINT ON (e:Email) ASSERT e.email IS UNIQUE;
CREATE CONSTRAINT ON (s:SSN) ASSERT s.ssn IS UNIQUE;
CREATE CONSTRAINT ON (p:Phone) ASSERT p.phoneNumber IS UNIQUE;
```

Personally, I like to implement these types of pre-requisite schema
queries by defining them in some sort of array:

```java
public class Cypher {
        public static final String[] SCHEMA_QUERIES = {
        // Core Types
        "CREATE CONSTRAINT ON (c:Client) ASSERT c.id IS UNIQUE",
        "CREATE CONSTRAINT ON (b:Bank) ASSERT b.id IS UNIQUE",
        "CREATE CONSTRAINT ON (m:Merchant) ASSERT m.id IS UNIQUE",
        "CREATE CONSTRAINT ON (m:Mule) ASSERT m.id IS UNIQUE",

        // Transaction Types
        "CREATE CONSTRAINT ON (c:CashIn) ASSERT c.id IS UNIQUE",
        "CREATE CONSTRAINT ON (c:CashOut) ASSERT c.id IS UNIQUE",
        "CREATE CONSTRAINT ON (d:Debit) ASSERT d.id IS UNIQUE",
        "CREATE CONSTRAINT ON (p:Payment) ASSERT p.id IS UNIQUE",
        "CREATE CONSTRAINT ON (t:Transfer) ASSERT t.id IS UNIQUE",
        "CREATE CONSTRAINT ON (tx:Transaction) ASSERT tx.id IS UNIQUE",

        // Identity Types
        "CREATE CONSTRAINT ON (e:Email) ASSERT e.email IS UNIQUE",
        "CREATE CONSTRAINT ON (s:SSN) ASSERT s.ssn IS UNIQUE",
        "CREATE CONSTRAINT ON (p:Phone) ASSERT p.phoneNumber IS UNIQUE",
        };
}
```

And then simply firing them off one at a time with a utility method like:

```java
import org.neo4j.driver.*;
import java.util.Arrays;

public class Database {
        public static void enforcePaySimSchema(Driver driver) {
                try (Session session = driver.session()) {
                        Arrays.stream(Cypher.SCHEMA_QUERIES).forEach(q -> session.run(q));
                }
        }
}
```


### Step 2: Iteratively Loading PaySim Transactions {#step-2-iteratively-loading-paysim-transactions}

Recall from [our previous post]({{< relref "paysim" >}}), we created an implementation of PaySim
that provides a simple Java `Iterator` that we can use to consume
transaction data.

But how do we get the Transactions into our graph?


#### Building a PaySim Transaction Cypher Query {#building-a-paysim-transaction-cypher-query}

We can take advantage of Cypher's `MERGE` clause[^fn:3] to do
double-duty and create our Client, Bank, and Merchant nodes while also
creating Transactions. There's a catch: you can't parameterize a label
in Cypher.

> While Cypher won't let you parameterize a node's label, APOC's
> `apoc.merge.node` procedure can do this for you if you're willing to
> use APOC.

Since we're using the Java Driver, we're already writing code, so
let's just make it a 2 step process:

1.  Fill in an initial query template, using placeholders for the
    node labels
2.  Create the Neo4j `Query` instance, adding our parameter values

Let's take a look at a condensed solution:

```java
import org.neo4j.driver.Query;
import org.paysim.base.Transaction;
import java.util.Map;

public class Cypher {
        public static final String SENDER_LABEL_PLACEHOLDER = "~STYPE~";
        public static final String RECEIVER_LABEL_PLACEHOLDER = "~RTYPE~";
        public static final String TX_LABEL_PLACEHOLDER = "~XTYPE~";

        public static final String INSERT_TRANSACTION_QUERY = String.join("\n", new String[] {
                  "MERGE (s:" + SENDER_LABEL_PLACEHOLDER + " { id: $senderId })",
                  "MERGE (r:" + RECEIVER_LABEL_PLACEHOLDER + " { id: $receiverId })",
                  "CREATE (tx:Transaction:" + TX_LABEL_PLACEHOLDER + " { id: $txId })",
                  "SET tx.ts = $ts, tx.amount = $amount, tx.fraud = $fraud,",
                  "    tx.step = $step, tx.globalStep = $globalStep",
                  "CREATE (s)-[:PERFORMED]->(tx)",
                  "CREATE (tx)-[:TO]->(r)",
          });
}

public class Util {
        public static Query compileTransactionQuery(Transaction t) {
                String rawQ = Cypher.INSERT_TRANSACTION_QUERY
                  .replace(Cypher.SENDER_LABEL_PLACEHOLDER, capitalize(t.getOrigType().toString()))
                  .replace(Cypher.RECEIVER_LABEL_PLACEHOLDER, capitalize(t.getDestType().toString()))
                  .replace(Cypher.TX_LABEL_PLACEHOLDER, capitalize(t.getAction()));
                Map<String, Object> props = propsFromTx(t);

                return new Query(rawQ, props);
    }
}
```

While maybe not the prettiest, it gets the job done! We templatize our
`MERGE` and `CREATE` clauses and use a helper function to take a given
PaySim `Transaction` and translate it into a Neo4j `Query` instance
ready for execution.


#### Batch Executing Cypher in Code {#batch-executing-cypher-in-code}

The best way to get high-throughput writes with a proper ACID database
like Neo4j is to minimize the total number of transactions you need to
perform. In the case of PaySim, a single simulation run with the
default settings can produce _millions of PaySim transactions._ Let's
look at how to take an optimal approach.

There are two common batch loading patterns when using Cypher from an
application utilizing a Neo4j driver:

1.  Open a _write transaction_ session and execute _many queries_
2.  Use Cypher's `UNWIND`[^fn:4] clause to iterate over a List of
    parameters in a _single query_

Which one should you use? Typically, the `UNWIND` approach is better
if you can massage your Cypher into utilizing it and can build up the
proper data structure of parameter values. Since we're changing labels
in our `MERGE=/=CREATE` clauses, we can't use `UNWIND` here unless we
want to write a very APOC-heavy query.

Luckily, the Neo4j drivers make it easy to take the first approach
using **Transaction functions**[^fn:5].

Let's write a simple helper function that takes an established
`Driver` connection and a `List` of Neo4j `Query` instances to execute:

```java
import org.neo4j.driver.*;
import java.util.List;

public class Database {
        public static int executeBatch(Driver driver, List<Query> queries) {
                try (Session session = driver.session()) {
                        int cnt = session.writeTransaction(tx -> {
                                  queries.forEach(q -> tx.run(q));
                                  return queries.size();
                        });
                        return cnt;
                }
        }
}
```

Now we just need to batch up the queries. There are probably a few
different approaches, but here's one approach we can take using a
mutable `List<Transaction>` that effectively acts as a queue we flush
at some regular interval.

```java
int batchSize = 500;
List<Query> batch = new ArrayList<>(batchSize);

// "sim" is an instance of IteratingPaySim and is already "running"
sim.forEachRemaining(t -> {
          batch.add(Util.compileTransactionQuery(t));

          if (batch.size() >= batchSize) {
                  Database.executeBatch(driver, batch); // our helper function
                  batch.clear();
          }
  });

// One last flush for any stragglers
if (batch.size() > 0) {
        Database.executeBatch(driver, batch);
}
```

In the above case, the driver will execute up to 500 queries per
transaction, limiting the total number of transactions the database
needs to log. Feel free to test out different batch sizes as they can
have varying results dependent on things like how large the JVM heap
is for the database, how many IOPS the underlyign storage layer
provides, and general CPU clock speed.


### Step 3. Disguising our Mules {#step-3-dot-disguising-our-mules}

In our previous step, we took the "type" of the agent from the
`Transaction`, so in situations where the agent was a Mule, the node
being merged only received a `:Mule` label.

Since we consider mules a type of Client, let's disguise them as
`:Client` nodes.

We do this with a simple bit of Cypher to first find all the Mules
we've yet to process and add an additional label to them:

```cypher
MATCH (m:Mule) WHERE NOT m:Client
SET m :Client
RETURN m.id
```

Since the number of mules in our simulation tend to be a fraction of
the total number of clients, running it is trivial and we don't need
to worry about Transaction functions and batching! Assuming we put the
above cypher into a `public static String` on our `Cypher` class:

```java
// "driver" is a connected Neo4j Driver instance
driver.session().run(Cypher.MAKE_MULES_CLIENTS);
```


### Step 4. Establishing Identities and their Relationships {#step-4-dot-establishing-identities-and-their-relationships}

At this point, we've got all our PaySim transactions and agents loaded
into the graph. Now, for every client in the simulation, we want to
create and connect their instances of identifiers through
relationships.

We can do so with a little bit of paramterized cypher:

```cypher
MERGE (c:Client {id: $clientId})
  ON MATCH SET c.name = $name
MERGE (s:SSN {ssn: $ssn})
MERGE (e:Email {email: $email})
MERGE (p:Phone {phoneNumber: $phoneNumber})
MERGE (c)-[:HAS_SSN]->(s)
MERGE (c)-[:HAS_EMAIL]->(e)
MERGE (c)-[:HAS_PHONE]->(p)
```

Like before in [step 2](#step-2-iteratively-loading-paysim-transactions), we'll utilize the same batching technique of
executing a set number of queries within a single database transaction
in order to increase throughput.

> In reality, this is a great candidate for the `UNWIND` approach
> mentioned [above](#batch-executing-cypher-in-code), but the author is lazy and didn't want to write more
> code :-)

```java
// Where "sim" is our IteratingPaySim instance and batchSize is previously defined
Lists.partition(sim.getClients(), batchSize).forEach(chunk -> {
          List<Query> queries = chunk.stream()
                .map(client -> Util.compileClientIdentityQuery(client.getClientIdentity()))
                .collect(Collectors.toList());
          Database.executeBatch(driver, queries);
  });
```

You'll notice that like before, we're building `List<Query>` that we
pass to our `Database.executeBatch()` helper method to run them within
the same transaction function.

However, **there's something new here:** `Lists.partition()`[^fn:6]

This comes from a Google's [Guava library](https://github.com/google/guava) and very nicely takes a
`java.util.List` and makes a "list of lists", partitioned into the
given size. Our code then works on taking batches of our PaySim
Clients and using transaction functions to bulk load the changes.


### Step 5. Updating Additional Node Properties {#step-5-dot-updating-additional-node-properties}


### Step 6. Thread Transactions into Chains {#step-6-dot-thread-transactions-into-chains}


## Putting it All Together {#putting-it-all-together}

Here's a glimpse at the finished product, specifically a look at the
core loading logic from the `App.run()` method.[^fn:7]

```java
public static void run(Config config) {
        IteratingPaySim sim = new IteratingPaySim(new Parameters(config.propertiesFile), config.queueDepth);

        final List<Query> batch = new ArrayList<>(config.batchSize);
        final ZonedDateTime start = ZonedDateTime.now();
        final AtomicInteger atom = new AtomicInteger(0);

        try (Driver driver = Database.connect(Database.defaultConfig, config.username, config.password)) {
            Database.enforcePaySimSchema(driver);

            try {
                sim.run();
                logger.info("Simulation started, load commencing...please, be patient! :-)");
                // Batch up Queries based on our Transaction stream for execution
                sim.forEachRemaining(t -> {
                    batch.add(Util.compileTransactionQuery(t));

                    if (batch.size() >= config.batchSize) {
                        atom.addAndGet(Database.executeBatch(driver, batch));
                        batch.clear();
                    }
                });

                // Anything left over?
                if (batch.size() > 0) {
                    atom.addAndGet(Database.executeBatch(driver, batch));
                }
                logger.info(String.format("[loaded %d PaySim transactions]", atom.get()));
                logger.info(String.format("[estimated load rate: %.2f PaySim-transactions/second]",
                        (float) atom.get() / Util.toSeconds(Duration.between(start, ZonedDateTime.now()))));

                logger.info("Labeling all Mules as Clients...");
                driver.session().run(Cypher.MAKE_MULES_CLIENTS);

                logger.info("Creating 'identity' materials associated with Client accounts...");
                Lists.partition(sim.getClients(), config.batchSize)
                        .forEach(chunk -> {
                            List<Query> queries = chunk.stream()
                                    .map(client -> Util.compileClientIdentityQuery(client.getClientIdentity()))
                                    .collect(Collectors.toList());
                            Database.executeBatch(driver, queries);
                        });

                logger.info("Setting any extra node properties for Merchants and Banks...");
                List<SuperActor> allActors = Streams.concat(
                        sim.getMerchants().stream(),
                        sim.getBanks().stream()).collect(Collectors.toList());
                Lists.partition(allActors, config.batchSize)
                        .forEach(chunk -> {
                            List<Query> queries = chunk.stream()
                                    .map(actor -> Util.compilePropertyUpdateQuery(actor))
                                    .collect(Collectors.toList());
                            Database.executeBatch(driver, queries);
                        });

                logger.info("Threading transactions...");
                final List<String> ids = Database.getClientIds(driver);
                Lists.partition(ids, config.batchSize).forEach(chunk -> {
                    Query query = new Query(Cypher.THREAD_TRANSACTIONS_IN_BATCH, Values.parameters("ids", chunk));
                    Database.execute(driver, query);
                });

            } catch (Exception e) {
                logger.error("EXCEPTION while loading data", e);
                try {
                    sim.abort();
                } catch (IllegalStateException ise) {
                    logger.warn("sim already aborted!");
                }
            }
        }

        Duration delta = Duration.between(start, ZonedDateTime.now());
        logger.info(String.format("Simulation & Load COMPLETED in %dm %ds", delta.toMinutes(), Util.toSecondsPart(delta)));
    }
```


## Let's Run It! 🏃 {#let-s-run-it}

Let's get down to business and run that code, shall we?

Assuming you've got the project cloned or downloaded and all the
[prerequisites](#prerequisites-for-you-home-gamers) in place, you can follow along.


### Tweak our Simulation Parameters {#tweak-our-simulation-parameters}


### Stage our Database {#stage-our-database}

If you use the default simulation parameters, you'll be producing a
graph with approximately:

-   TKTKT nodes
-   TKTKT relationships

Which will translate to approximately:

The default settings from Neo4j will suffice, but you may want to bump
things up a small amount by editing the `neo4j.conf` file to change
some heap and pagecache settings:

```properties
dbms.memory.heap.initial_size=1G
dbms.memory.heap.max_size=1G
dbms.memory.pagecache.size=1.5G
```


### Build the Demo Project {#build-the-demo-project}

```shell
# build and package the demo
./gradlew distZip

# unpack a copy that contains all deps and start scripts
cd build/distributions
unzip paysim-demo-0.2.0.zip
cd paysim-demo-0.2.0

# validate you can run the demo by checking the program's help output
./bin/paysim-demo -h

```

```powershell
# build and package the demo
.\gradlew.bat distZip

# unpack a copy that contains all deps and start scripts
cd build\distributions
Expand-Archive -Force .\paysim-demo-0.2.0.zip .
cd paysim-demo-0.2.0

# validate you can run the demo by checking the program's help output
bin\paysim-demo.bat -h

```


### Run the Simulation {#run-the-simulation}


### Confirm our Graph is Loaded {#confirm-our-graph-is-loaded}


## Wrapping Up {#wrapping-up}


## Next Time: Analyzing our Graph {#next-time-analyzing-our-graph}

We've now covered some [background on PaySim]({{< relref "paysim" >}}) and, in this post, covered
how to take PaySim and populate a Neo4j graph database.

<a id="orgb9d45b9"></a>

{{< figure src="/img/paysim-bloom-preview.jpg" caption="Figure 2: A preview of what's to come" >}}

Next we'll look at ways to exploit the connectedness of the graph to
identify fraudulent transactions and mule accounts.

_Tot ziens!_

[^fn:1]: <https://github.com/voutilad/paysim>
[^fn:2]: I recommend using an OpenJDK from <https://adoptopenjdk.net/>
[^fn:3]: <https://neo4j.com/docs/cypher-manual/3.5/clauses/merge/>
[^fn:4]: <https://neo4j.com/docs/cypher-manual/3.5/clauses/unwind/>
[^fn:5]: See <https://neo4j.com/docs/driver-manual/1.7/sessions-transactions/#driver-transactions-transaction-functions> for more details. Transaction functions are supported across many driver languages including: C#, Go, Java, JavaScript, and Python. A major nicety of transaction functions is they can handle transient errors automatically and use retries without any additional code.
[^fn:6]: <https://guava.dev/releases/snapshot/api/docs/com/google/common/collect/Lists.html#partition-java.util.List-int>-
[^fn:7]: <https://github.com/voutilad/paysim-demo/blob/a72a8e6172b0d58ae9c340c65386f96adc0acc95/src/main/java/io/sisu/paysim/App.java>
