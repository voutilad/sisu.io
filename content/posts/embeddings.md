+++
title = "(draft) Bringing traditional ML to your Neo4j Graph with node2vec"
author = ["Dave Voutila"]
description = "Let's take a look at using graph embeddings with traditional ML tools"
date = 2020-07-08
images = ["../static/img/node2vec-walk.png"]
lastmod = 2020-07-08T13:21:45-04:00
tags = ["neo4j", "data-sience"]
draft = false
+++

<div class="ox-hugo-toc toc">
<div></div>

<div class="heading">Table of Contents</div>

- [node2what-now? 🤔](#node2what-now)
- [The Les Misérables Data Set](#the-les-misérables-data-set)
- [Using node2vec](#using-node2vec)
- [Reproducing Grover & Leskovec's Findings](#reproducing-grover-and-leskovec-s-findings)
- [The Demonstration](#the-demonstration)
- [Where can we go from here?](#where-can-we-go-from-here)
- [Appendix: Neo4j's Python Driver and SciKit Learn](#appendix-neo4j-s-python-driver-and-scikit-learn)

</div>
<!--endtoc-->

<a id="orge31e7be"></a>

{{< figure src="/img/node2vec-handsketch.png" caption="Figure 1: Graph Embeddings are Magical!" >}}

<summary>
Departing for once from my posts involving financial fraud topics,
let's take more of a functional look at an upcoming capability in the
new Neo4j Graph Data Science library (v1.3) called "graph embeddings."
</summary>

Since most machine learning and artificial intelligence applications
expect someone to present them just numerical representations of the
real world, some non-trivial amount of time is spent turning pictures
of cats on the internet into 1's and 0's. You can do the same with
your graphs, but there's a catch.

> A disclaimer: this post was written using a pre-release of v1.3 of
> the Graph Data Science library and some of the examples here may need
> tuning, especially since the node2vec implementation is still in an
> alpha[^fn:1] state.


## node2what-now? 🤔 {#node2what-now}

As the name implies, [node2vec](https://snap.stanford.edu/node2vec/) creates **node** embeddings for the given
nodes of a graph, generating a _d_-dimensional feature vector for each
node where _d_ is a tunable parameter in the algorithm.

<a id="orgb02f0e9"></a>

{{< figure src="/img/node2vec-walk.png" caption="Figure 2: A biased random walk with node2vec (image from the paper)" >}}

Ok...so what's the point?

Given an arbitrary graph, how can you scalably generate feature
vectors? For small graphs, we could make something pretty trivial by
hand. But as graphs grow or are have unknown characteristics you'll
need a general approach that can learn features from the graph and do
so at scale.

This is where _node2vec_ comes in. It utilizes a combination of
feature learning with a random walk to generalize and scale.

The nitty-gritty is beyond the scope of this blog post, so if you're
of an academic mindset I recommend reading Grover and Leskovec's paper
[node2vec: Scalable Feature Learnings for Networks](https://arxiv.org/pdf/1607.00653.pdf).


## The Les Misérables Data Set {#the-les-misérables-data-set}

Similar to Neo4j's often demo'd [Game of Thrones](https://neo4j.com/blog/graph-of-thrones/) data set, let's take
look at one used by the node2vec authors related to co-appearances in
the Victor Hugo novel _Les Misérables_.

> And just like Game of Thrones, I haven't read Les Misérables. Shhh!


### Prerequisites {#prerequisites}

Graph a copy of [Neo4j 4.1](https://neo4j.com/download-center), ideally a copy of [Neo4j Desktop](https://neo4j.com/download) to make it
easier for yourself if you're not familiar with installing plugins,
etc. (See the [getting started guide](https://neo4j.com/developer/neo4j-desktop/) if you're new to this stuff.)

You'll need the latest supported APOC and Graph Data Science plugins
as well.


### Loading the Data {#loading-the-data}

I've transformed a publicly available data set from Donald Knuth's
_"The Stanford GraphBase: A Platform for Combinatorial
Computing"_[^fn:2] into a JSON representation easily loaded via [APOC](https://neo4j.com/docs/labs/apoc/4.0/)'s
json import procedure.

It doesn't get much easier than this:

```cypher
CALL apoc.import.json('https://www.sisu.io/data/lesmis.json')
```

You should now have a graph with 77 nodes (each with a `Character`
label) connected to one another via a `APPEARED_WITH` relationship
containing a `weight` numerical property.

<a id="org434fd69"></a>

{{< figure src="/img/lesmis_appearances.svg" caption="Figure 3: Initial overview of our Les Mis network" >}}

> While we've loaded it as a directed graph (because all relationships in
> Neo4j must have a direction), our data set is really representing an
> undirected graph.

Feel free to explore it a little. One of the interesting things is
this data set already contains some modularity-based clustering (since
I got the source data from the [Gephi](https://gephi.org) project). We'll use this later to
compare/contrast our output.


## Using node2vec {#using-node2vec}

Now that we've got our undirected, monopartite[^fn:3] graph how do we
use **node2vec**? Just like other GDS algorithms, we define our _graph
projection_ and set some algorithm specific parameters.

In the case of **node2vec**, the parameters we'll tune are:

`embeddingSize`
: _(integer)_ The number of dimensions of the resulting feature
    vector


`returnFactor`
: _(double)_ Likelyhood of returning to the prior node in the
    random walk (referred to as _p_ in the node2vec paper)


`inOutFactor`
: _(double)_ Bias parameter for how likely the random walk will
    explore distant nodes vs. closer nodes in the graph (reffered to as
    _q_ in the node2vec paper)


`walkLength`
: _(integer)_ The length of each random walk

> Note: All of the above parameters take non-negative values. 😉

Using parameter placeholders, here's what a call to node2vec looks
like using an anonymous, native graph projection:

```cypher
CALL gds.alpha.node2vec.stream({
  nodeProjection: 'Character',
  relationshipProjection: {
  EDGE: {
    type: 'APPEARED_WITH',
    orientation: 'UNDIRECTED'
  },
  embeddingSize: $d,
  returnFactor: $p,
  inOutFactor: $q,
  walkLength: $l
}) YIELD nodeId, embedding
```


## Reproducing Grover & Leskovec's Findings {#reproducing-grover-and-leskovec-s-findings}

In their paper, the authors leverage the Les Mis' data set to
illustrate the tunable return (_p_) and in-out (_q_) parameters and
how they influence the resulting feature vectors and, consequently,
the impact to the output of a **_k_-means clustering** algorithm. Let's
use Neo4j's _node2vec_ algorithm and see how we can reproduce Grover &
Leskovec's case study in the Les Mis network[^fn:4].

<a id="org114c7f8"></a>

{{< figure src="/img/node2vec-original.png" caption="Figure 4: Grover and Leskovec's \"complementary visualizations of Les Mis...\" showing homophily (top) and structural equivalence (bottom) where colors represent clusters" >}}


### What did they demonstrate? {#what-did-they-demonstrate}

The author's used the Les Mis network to show how node2vec can
discover embeddings that obey the concepts of _homophily_ and
_structural equivalence_. What does that mean?

**homophily**
: One definition outside math is "the tendency of
    individuals to associate with others of the same kind"[^fn:5]. This
    means favoring nodes in a given node's neighborhood. (See the top
    part of _fig 4_.)


**structural equivalence**
: Two nodes are _structurally equivalent_
    if they have the same relationships (or lack thereof) to all other
    nodes[^fn:6]. (See the bottom part of _fig 4_.)

In terms of Les Mis, **homophily** can be thought of as clusters of
Characters that frequently appear with one another. Basically the
traditional idea of "communities."

For **structured equivalence**, the example the authors provide is the
concept of "bridge characters" that span sub-plots in the Les Mis
storyline. These characters might not be part of traditional
communities, but act as ways to connect disparate communities. (You
might recall my

Let's see if we can use the parameters they mentioned and a _k_-means
implementation to recreate something similar to their output in
_Figure 2._


### Our Methodology {#our-methodology}

Since Grover & leskovec don't mention exactly how they arrived at
their Les Mis output, we're going to try using the following
methodology:

1.  **Populate Neo4j** with the Co-appearance graph -- We've already done
    this part in [Loading the Data](#loading-the-data) above!
2.  **Refactor the graph** to accomodate unweighted edges -- The current
    alpha node2vec implementation doesn't support weights yet, but we
    can achieve the same result through a structural change.
3.  **Generate node embeddings**.
4.  Run the embeddings through [scikitlearn's **KMeans algorithm**](https://scikit-learn.org/stable/modules/clustering.html#k-means).
5.  **Update the nodes** their cluster assignments, writing back to Neo4j.
6.  **Visualize the results** with [Neo4j Bloom](https://neo4j.com/bloom/).

Now, let's get to it!


## The Demonstration {#the-demonstration}

We've already got the data loaded, so let's skip to step 2.


### Refactoring the Graph {#refactoring-the-graph}

Since the **node2vec** implementation doesn't support weighted edges
(yet!), we can achieve the same effect with a simple
refactor. Ultimately, we want the number of co-appearances to be the
weight of the edge between two characters and that's what the `weight`
relationship property currently represents.

Since the weight needs to influece the _search bias_ in the node2vec
algorithm, we want to increase the probability of a visit to a
neighboring node that has a higher weight. How can we do that? **Adding
multiple edges between nodes!**

Let's take an example:

```cypher
// Let's look at 2 characters and how they're related
MATCH p=(c1:Character)-[]-(c2:Character)
WHERE c1.name IN ['Zephine', 'Dahlia']
  AND c2.name IN ['Zephine', 'Dahlia']
RETURN p
```

<a id="org506fb36"></a>

{{< figure src="/img/zephy_dahlia_1.svg" caption="Figure 5: Zephine and Dahlia (original)" >}}

In this case, their `APPEARED_WITH` relationship has a weight of
`4.0`. (Not visible in the figure, so trust me!)

What we really want are **4 edges** between them, so we can do a little
refactoring of our graph:

```cypher
MATCH (c1:Character)-[r:APPEARED_WITH]->(c2:Character)
UNWIND range(1, r.weight) AS i
  MERGE (c1)-[:UNWEIGHTED_APPEARED_WITH {idx:i}]->(c2)
```

Now let's look at Zephone and Dahlia again:

<a id="orga666fb9"></a>

{{< figure src="/img/zephy_dahlia_2.svg" caption="Figure 6: Zephine and Dahlia (now including unweighted edges)" >}}

We've now got 4 distinct `UNWEIGHTED_APPEARED_WITH` edges between
them. (Yes, I'm pretty verbose with my naming!)


### Generating the Embeddings {#generating-the-embeddings}

This part is made super simple by the GDS library, as we saw above in
the [using node2vec introduction](#using-node2vec). We just need to make sure to update
the projection and set our parameters.

To start, for the _homophily_ example we set `p = 1.0, q = 0.5, d =
16` per Grover & Leskovec's case study.

```cypher
CALL gds.alpha.node2vec.stream({
  nodeProjection: 'Character',
  relationshipProjection: {
    EDGE: {
      type: 'UNWEIGHTED_APPEARED_WITH',
      orientation: 'UNDIRECTED'
    }
  },
  returnFactor: 1.0, // parameter 'p'
  inOutFactor: 0.5,  // parameter 'q'
  embeddingSize: 16  // parameter 'd'
})
```

For our _structured equivalence_ example, the authors set `p = 1.0, q
= 2.0, d = 16` (in effect, only `q` changes):

```cypher
CALL gds.alpha.node2vec.stream({
  nodeProjection: 'Character',
  relationshipProjection: {
    EDGE: {
      type: 'UNWEIGHTED_APPEARED_WITH',
      orientation: 'UNDIRECTED'
    }
  },
  returnFactor: 1.0, // parameter 'p'
  inOutFactor: 2.0,  // parameter 'q'
  embeddingSize: 16  // parameter 'd'
})

```

What do some of the some of our embeddings results look like? Let's
take a look in Neo4j Browser:

<a id="orgabb9353"></a>

{{< figure src="/img/example_embeddings.png" caption="Figure 7: Here, have some node embeddings!" >}}

You'll notice your results differ from mine, regardless of which of
the above examples you run. (If not...I'd be a bit surprised!) Given
the random nature of the walk, the specific values themselves aren't
interesting or have any reasonable representation. You should see, for
each node, a **_16_-dimensional feature vector** since we set our
dimensions parameter `d = 16`.

The idea here is the features as a whole describe the nodes with
respect to each other. _So don't worry if you can't make heads or
tails of the numbers!_


### Clustering our Nodes with _K_-Means {#clustering-our-nodes-with-k-means}

This is where things get a bit fun as you should now be wondering "how
do I get the data out of Neo4j and into SciKit Learn?!"

We're going to use the [Neo4j Python Driver](https://neo4j.com/docs/api/python-driver/current/) to orchestrate running our
GDS algorithms and feeding the feature vectors to a _k_-means
algorithm.


#### Bootstrapping your Python3 environment {#bootstrapping-your-python3-environment}

In the interest of time, I've done the hard part for you. You can `git
clone` [my les-miserables](https://github.com/neo4j-field/les-miserables) project locally and do the following to get going.

<!--list-separator-->

-  Create your Python3 Virtual Environment

    After cloning or downloading the project, create a new Python virtual
    environment (this assumes a unix-like shell...adapt for Windows):

    ```sh
    $ python3 -venv .venv
    ```

<!--list-separator-->

-  Activate the environment

    ```sh
    $ . .venv/bin/activate
    ```

<!--list-separator-->

-  Install the dependencies using PIP

    ```sh
    $ pip install -r requirements.txt
    ```

    You should now have `scikit-learn` and `neo4j` packages
    available. Feel free to test by opening a Python interpreter and
    trying to `import neo4j`, etc.


#### Using my provided Python script {#using-my-provided-python-script}

I've provided an implementation of the Python Neo4j driver as well as
the SciKit Learn KMeans algorithm so we won't go into details on
eithers inner workings here. The script (`kmeans.py`)[^fn:7] takes a variety
of command line arguments allowing us to tune the parameters we
want.

You can look at the usage details using the `-h` flag:

```sh
$ python kmeans.py -h
usage:   kmeans.py [-A BOLT URI default: bolt://localhost:7687] [-U USERNAME (default: neo4j)] [-P PASSWORD (default: password)]
supported parameters:
        -R RELATIONSHIP_TYPE (default: 'UNWEIGHTED_APPEARED_WITH'
        -L NODE_LABEL (default: 'Character'
        -C CLUSTER_PROPERTY (default: 'clusterId'
        -d DIMENSIONS (default: 16)
        -p RETURN PARAMETER (default: 1.0)
        -q IN-OUT PARAMETER (default: 1.0)
        -k K-MEANS NUM_CLUSTERS (default: 6)
        -l WALK_LENGTH (default: 80)
```

Easy, peasy! (See the [appendix](#appendix-neo4j-s-python-driver-and-scikit-learn) for details on the Python
implementation.)

The paper mentions what to set `p` and `q` to, but what about the
number of clusters? If you count the distinct colors in their visual,
we can see they use the following:

-   **six** clusters for the **homophily** demonstration
-   **three** clusters for the **structural equivalence** demonstration

So we'll set `k` accordingly.

Do one run for the **homophily** output and one for the **structured
equivalence** case (adust the bolt, username, and password params as
needed for your environment) using our parameters for `p`, `q`, and
`k`:

```sh
$ python kmeans.py -p 1.0 -q 0.5 -k 6 -C homophilyCluster
Connecting to uri: bolt://localhost:7687
Generating graph embeddings (p=1.0, q=0.5, d=16, l=80, label=Character, relType=UNWEIGHTED_APPEARED_WITH)
...generated 77 embeddings
Performing K-Means clustering (k=6, clusterProp='homophilyCluster')
...clustering completed.
Updating graph...
...update complete: {'properties_set': 77}
```

And another run changing `q = 2.0` to bias towards structured
equivalence and `k = 3`:

```sh
$ python kmeans.py -p 1.0 -q 2.0 -k 3 -C structuredEquivCluster
Connecting to uri: bolt://192.168.1.167:7687
Generating graph embeddings (p=1.0, q=0.5, d=16, l=80, label=Character, relType=UNWEIGHTED_APPEARED_WITH)
...generated 77 embeddings
Performing K-Means clustering (k=6, clusterProp='structuredEquivCluster')
...clustering completed.
Updating graph...
...update complete: {'properties_set': 77}
```

> ⚠ **HEADS UP!** Make sure you use the same cluster output properties (`-C`
> settings) so they line up with the Bloom perspective I provide!

Nice...but how should we visualize the output?


### Visualizing with Neo4j Bloom {#visualizing-with-neo4j-bloom}

If you took my advice and used Neo4j Desktop, you'll have a copy of
Neo4j Bloom available for free. If not, you're on your own here and
you'll have to just follow along. (Sorry...not sorry.)


#### Configuring our Perspective {#configuring-our-perspective}

Bloom relies on "perspectives" to tailor the visual experience of the
graph. I've done the work for you (you're welcome!) and you can
download the json file [here](https://raw.githubusercontent.com/neo4j-field/les-miserables/master/LesMis-perspective.json) or find `LesMis-perspective.json` in the
GitHub project you cloned earlier.

<a id="orgd0b468c"></a>

{{< figure src="/img/bloom-perspective-import.png" caption="Figure 8: Click the Import button...it's pretty easy!" >}}

Follow the [documentation](https://neo4j.com/docs/bloom-user-guide/current/bloom-perspectives/#%5Fcomponents%5Fof%5Fa%5Fperspective) on installing/importing a perspective if you
need help.


#### Visualize the graph {#visualize-the-graph}

Let's pull back a view of all the Characters and use the original
`APPEARED_WITH` relationship type to connect them.

<a id="org3ae5e43"></a>

{{< figure src="/img/bloom-lesmis-query.png" caption="Figure 9: Query for Characters that have a APPEARED\_WITH relationship" >}}

You should get something looking like the following:

<a id="org0469329"></a>

{{< figure src="/img/lesmis-network.png" caption="Figure 10: The LesMis Network" >}}

There aren't any colorful clusters and things look pretty messy to me!
Let's toggle the conditional styling to show the output of our
clustering.

Using the Bloom node style pop-up menus, you can toggle the
perspective's pre-set rule-based styles:

<a id="orgf86c00d"></a>

{{< figure src="/img/lesmis-homophily-setting.png" caption="Figure 11: Toggling conditional styling in Bloom" >}}

You should now have a much more colorful graph to look at and let's
dig into what we're seeing.


### Our Homophily Results {#our-homophily-results}

What should you be seeing at this point? Since we generated embeddings
that leaned towards expressing homophily, we should see some obvious
communities assigned distinct colors based on the _k_-means clustering
output.

<a id="org6ef7100"></a>

{{< figure src="/img/lesmis-homophily.png" caption="Figure 12: Our homophily results: some nice little clusters!" >}}

Not bad! Looks similar to the top part of our [screenshot](#reproducing-grover-and-leskovec-s-findings) from the
node2vec paper.

How about the structural equivalence results?


### Our Stuctural Equivalence Results {#our-stuctural-equivalence-results}

Oh...oh no. This looks nothing like what is in the node2vec paper!

<a id="org7d40bde"></a>

{{< figure src="/img/lesmis-not-structured.png" caption="Figure 13: Structural Equivalance results that are...less than ideal!!" >}}

What went wrong?! We expected to see something that doesn't look like
typical communities and instead showing the idea of "bridge
characters" (recall from [our previous definitions](#what-did-they-demonstrate) of structural
equivalence).


#### Remember our Walk Length parameter? {#remember-our-walk-length-parameter}

Earlier I mentioned that the Les Mis network has only 77 nodes. It's
extremely small by any means. Can you remember what the current
default _walk length_ parameter is for the node2vec implementation?

> Here's a hint: it defaults to `80` 😉

That's fine for our homophily example as the idea was to account for
global structure of the graph and build communities. But for finding
"bridge characters", we really care about _local_ structure. (A bridge
character bridges close-by clusters and sits between them so should
have little to no relation to a "far away" cluster.)


#### Let's re-run with a new walk length {#let-s-re-run-with-a-new-walk-length}

So what should we use? Well, I did some testing, and found that `l =
7` is a pretty good setting. It's "local enough" to capture bridging
structure without biasing towards global clusters.

Using the script, add the `-l` command line argument like so:

```sh
$ python kmeans.py -p 1.0 -q 2.0 -k 3 -C structuredEquivCluster -R UNWEIGHTED_APPEARED_WITH -l 7
```

Here's what it looks like now:

<a id="org9eb7fd3"></a>

{{< figure src="/img/lesmis-structured.png" caption="Figure 14: Structural Equivalance, for real this time." >}}

That's much, much more like the original findings from the paper!

If you count, we get our expected 3 different colors (since in this
case we set `k = 3`) and if we look at the **blue** nodes they tend to
connect the reds and purple-ish colored nodes. It's not a perfect
reproduction of the paper's image, but keep in mind the authors never
shared their exact parameters!

> Note: since we're using such a small network in these examples, you
> might have some volatility in your results using a short walk
> length. That's ok! Remember it's a _random_ walk. In practice you'd
> most likely use a much larger (i.e. well more than 77 nodes) graph and
> locality would be more definable.


## Where can we go from here? {#where-can-we-go-from-here}

One area worth exploring is how to better integrate Neo4j into your
existing ML workflows and pipelines. In the above example, we just
used the Python driver and anonymous projections to integrate
something pretty trivial...but you probably need to handle much larger
data sets in your use cases.

One possibility is leveraging Neo4j's _Apache Kafka_ integration in
the **neo4j-streams** plugin. Neo4j's Ljubica Lazarevic provides an
overview in her January 2019 post: _[How to embrace event-driven graph
analytics using Neo4j and Apache Kafka](https://www.freecodecamp.org/news/how-to-embrace-event-driven-graph-analytics-using-neo4j-and-apache-kafka-474c9f405e06/)_


## Appendix: Neo4j's Python Driver and SciKit Learn {#appendix-neo4j-s-python-driver-and-scikit-learn}

Here are some code snippets that help show what's going on under the
covers in the `kmeans.py` script. A lot of the code is purely
administrative (dealing with command line args, etc.), but there are
two key functions.


### Extracting the Embeddings {#extracting-the-embeddings}

How do you run the GDS node2vec procedure and get the embedding
vectors? This is one way to do it, but the key part is using
`session.run()` and adding in the query parameters.

```python
def extract_embeddings(driver, label=DEFAULT_LABEL, relType=DEFAULT_REL,
                       p=DEFAULT_P, q=DEFAULT_Q, d=DEFAULT_D, l=DEFAULT_WALK):
    """
    Call the GDS neo2vec routine using the given driver and provided params.
    """
    print("Generating graph embeddings (p={}, q={}, d={}, l={}, label={}, relType={})"
          .format(p, q, d, l, label, relType))
    embeddings = []
    with driver.session() as session:
        results = session.run(NODE2VEC_CYPHER, L=label, R=relType,
                              p=float(p), q=float(q), d=int(d), l=int(l))
        for result in results:
            embeddings.append(result)
    print("...generated {} embeddings".format(len(embeddings)))
    return embeddings
```

Where `NODE2VEC_CYPHER` is our Cypher template:

```python
NODE2VEC_CYPHER = """
CALL gds.alpha.node2vec.stream({
  nodeProjection: $L,
  relationshipProjection: {
    EDGE: {
      type: $R,
      orientation: 'UNDIRECTED'
    }
  },
  embeddingSize: $d,
  returnFactor: $p,
  inOutFactor: $q
}) YIELD nodeId, embedding
"""
```


### Clustering with SciKit Learn {#clustering-with-scikit-learn}

Our above function returns a List of Python dicts, each with a
`nodeId` and `embedding` key where the `embedding` is the feature
vector (as a Python List of numbers).

To use _SciKit Learn_, we need to generate a dataframe using _NumPy_,
specifically the _array()_ function. Using a list comphrension, it's
easy to extract out just the feature vectors from the
`extract_embedding` output:

```python
def kmeans(embeddings, k=DEFAULT_K, clusterProp=DEFAULT_PROP):
    """
    Given a list of dicts like {"nodeId" 1, "embedding": [1.0, 0.1, ...]},
    generate a list of dicts like {"nodeId": 1, "valueMap": {"clusterId": 2}}
    """
    print("Performing K-Means clustering (k={}, clusterProp='{}')"
          .format(k, clusterProp))
    X = np.array([e["embedding"] for e in embeddings])
    kmeans = KMeans(n_clusters=int(k)).fit(X)
    results = []
    for idx, cluster in enumerate(kmeans.predict(X)):
        results.append({ "nodeId": embeddings[idx]["nodeId"],
                         "valueMap": { clusterProp: int(cluster) }})
    print("...clustering completed.")
    return results
```

The last part, after using `KMeans`, is constructing a useful output
for populating another Cypher query template. My approach creates a
List of dicts that like:

```python
[
    { "nodeId": 123, "valueMap": { homophilyCluster: 3 } },
    { "nodeId": 234, "valueMap": { homophilyCluster: 5 } },
    ...
]
```

Which drives the super simple, 3-line bulk-update Cypher template:

```python
UPDATE_CYPHER = """
UNWIND $updates AS updateMap
    MATCH (n) WHERE id(n) = updateMap.nodeId
    SET n += updateMap.valueMap
"""
```

Using Cypher's `UNWIND`, we iterate over all the dicts. The `MATCH`
finds a node using the internal node id (using `id()`) and then
updates properties on the matched node using the `+=` operator and the
`valueMap` dict.

[^fn:1]: What's _alpha_ state mean? See the GDS documentation on the different algorithm support tiers: <https://neo4j.com/docs/graph-data-science/current/algorithms/>
[^fn:2]: D. E. Knuth. (1993). The Stanford GraphBase: A Platform for Combinatorial Computing, Addison-Wesley, Reading, MA
[^fn:3]: Monopartite graphs are graphs where all nodes share the same label or type...or lack labels.
[^fn:4]: See section _4.1 Case Study: Les Misérables network_ in the node2vec paper
[^fn:5]: See <https://en.wiktionary.org/wiki/homophily>
[^fn:6]: See <http://faculty.ucr.edu/~hanneman/nettext/C12%5FEquivalence.html#structural>
[^fn:7]: Source code is also here: <https://github.com/neo4j-field/les-miserables/blob/master/kmeans.py>
