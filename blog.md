# in the begining
With the release of the OnePub beta, I thought the development process behind
OnePub might make an interesting read, because it has certainly been in interesting ride.

This is the story of our tech startup and how we brought OnePub to market.

So let's go back to the very beginning.

Our story has a few twists and turns as we navigated our way through a plethoria of competing solutions.

Perhaps, for you the reader, the most interesting is that 
we didn't use Flutter for our web interface, but not for the reasons that you think.

As a bonus, we've have peppered the article, with a few little known stats about pub.dev.

But I get ahead of myself; let's go back to the begining.

I first started using Dart sometime around the release of 2.1.

# crazy, delivers innovation
We had this crazy idea to build an entire business phone system into an app.

As web developers, with no mobile app experience, we were not keen on the idea of building a pair
of mobile apps from scratch.

## pwa
So our first thought was to build a [PWA](https://en.wikipedia.org/wiki/Progressive_web_application) (a website that looks like an app) designed for a mobile device.

We had a pre-existing stable webstack and delivering a mobile friendly PWA looked easy.

Problems however surfaced rather quickly. We needed access to a user's contact list, push notifications and the dial pad.

For that, we were going to need an actual app, bugger!

## cordova
OK, so a simple PWA wasn't going to work, what about a hybrid system like Cordova.

This look promising until we looked at the available plugins. There was a plugin that allowed
access to contacts but it appear to be no longer supported and in fact the enitre
Cordova plugin system looked thin on the ground.

## react native
Alright then, let's take a look at React Native.

The aim was to use the React Native webview to host our web app and then use react to call
into the mobile device.
I honestly don't remember the reason why we dumped React Native, but I do recall trying to
wrangle access to the host device from the webview and realizing that it was a complete hack. 

On top of that was the whole Javascript thing.  

The bottom line was, we were getting no where fast.

## flutter
We were now a coupole of month into development, prototyping in HTML, and still without a clear path forward.
So time to review the options once more. It was this moment in time that one of our System Admins (Peter)
reminded us that he had suggested this framework called Flutter and that maybe we should
go back and take a look at it ( and that we should have listened to him the first time around - OK fair point ).

And this is where my Dart journey started.

# new beginings

For a number of commercial reason our crazy Flutter project was cancelled but it didn't matter, I was already hooked on Dart.

I started building the [DCli console SDK for Dart](https://onepub.dev/packages/dcli) and rewote our entire production build and deployment using Dart and DCli.

I hadn't had some much fun coding in a very long time.

Over the next couple of years I published almost 40 packages to pub.dev and contributed PR's to a similar no. of projects.

It was during this journey that I realized that I needed a private repository and there really wasn't anything out there that
delivered what I thought I needed.

So in December of 2021 I decided to form a new company and build one.

# intent
I had essentially bet my house on my belief that flutter was going to become the dominant GUI framework, so this idea had better work and the Flutter community thrive.

The first questions we needed to answer were:
* exactly what part of the eco system are we trying to fill?
* what are dart developers looking for?
* what do we think the user journey will look like?
* how do we ensure that our actions don't undermine pub.dev?
* how do we market and monetise the service?
* how much are developers prepared to pay for the service?


We started by  interviewing a few external Dart developers and recieved positive feedback but that still isn't the same as having them take out their credit card to pay for a service.

Did a market exist , would developers pay for it?

Next, we had a hard look at some of the existing players in the repository market (such as NPM) on the basis that if developers where paying for NPM then logically the should pay for a Dart repository.

The comparision however wasn't conclusive as each of the providers, offer other services beyond just a repository and many of those services don't make sense within the Dart eco system.

> At some point, a `leap of faith` was required.

So into madness we journeyed.


## first rate experience
The developer experience was the next big issue. 

Very early on the process, we decieded that we wanted to closely mimic the pub.dev interface. 

We had two reasons for this; 
1) it was a fairly well thought out interface 
2) our users wouldn't need to learn how to use OnePub

The second point was really the driver behind the decision to mimic pub.dev.

We also wanted to the CLI user experience to be 'native'.

TODO: should this be under platform evolution ??

As a Java/Dart developer I really hate when I get told to install Python, Ruby or some other runtime to work with Java/Dart tools. I also hate it when I have to do a whole chunk of work to integrate the tooling into my existing processes. For me, this meant that the OnePub CLI tooling had to be written in Dart and work with the existing Dart CLI tooling seamlessly.

Fortunately for us, with the release of Dart 2.15, Dart officially supported private repositories. This still meant that we had a problem with pre 2.15 users.

Big organisations are more likely to pay for our service and are more likely to be using an older version of Dart due to their slower upgrade cycles.

So the question was, how do we support pre 2.15 customers?

For pre-2.15 users, we built a replacement tool for the `dart pub` command called `opub`. The opub command is simply a back port of the `dart pub` code.  

Surely we had now done enough?

But No, unfortunately/fortunately the dart pub code is null safe. So this limited our users to using at least Dart 2.12.  

But we wanted more. I wanted the steak knives and not those cheap ones with the plastic handles.

So for pre 2.12 users we had to provide an AOT compiled version of opub which would work for with pre-2.12 versions of Dart. Fortunately this is an area we have a lot of experience with.

The OnePub team are the developers of the dswitch package which like 'fvm' allows you to switch between versions of dart (use fvm for a Flutter install and dswitch for a Dart install).

The OnePub team are also the developers of DCli which provides an AOT compiled versions for Windows, MacOS and Linux via our github repository and as well as providing the ability to compile a package directly from .pub-cache.

Use DCli and Dswitch allows to provide support for pre 2.12 users, via multiple paths, allowing them to choose the option they felt most comfortable with.

1) simply download a pre-compiled exe from out github repository
2) use dswitch or fvm to switch to a current version of Dart, and use DCli's ability to compile a package from pub-cache, then switch back to their daily Dart version.

It would be so nice to be involved in a project where there is a simple straight path to the solutions, but alas no.

### search
With the CLI tooling sorted, what do we need to provide a premium user experience?

As we worked through use cases, we realiszed that we were forcing our private package users to switch between OnePub and pub.dev to search. This didn't seem like a seamless experience.

It was at this moment that we decieded we needed a complete replica of the pub.dev database so we could provide a single search interface for public and private packages.

TODO: I think this needs re-wording - deleting

This moment actually caused some agnst. Our aim was to improve the Dart eco system however our early concern was the possiblity that we bifurcat Dart package search by trying to surplant pub.dev.

On the flip side it presented a marketing opportunity. If we provided enough value add, that we became the preferred search interface then we would be front and centre in a user's minds when they needed a private package repository.

So how do we protect the community whilst building a market for our own product? 
In review we didn't see that offering an alternate public search interface would undermine pub.dev.
We have no intention of offering the ability to directly publish a public package to OnePub




TODO: talk about pub search and dart doc




# commencement

Worked started on OnePub in Janurary of 2022, initially just me, but eventually my brother Robert joined the project, both of us still holding down another job.

From early Janurary to mid July, I worked 7 days a week on the project, doing an averaging 80 hrs a week, with a single long weekend off in March.

From inception to the release of a beta, I estimate that we put in about a man year of development.




# platorm evolution
So, here we were, once again at the start of product development cycle, with no net, and I had literally bet the house on it.

In order to survive we needed a platform that would allow rapid upfront development but still allows us to grow and maintain the system long term without significant re-writes.

So what tech do we use?

The first question was, what did we need to build. We identified a number of discrete subsystems:
* CLI tooling
* the respository server ( used by `dart pub get` etc )
* web application
* api documentation service
* sundry support services (backups, security systems, web proxy, database, full text search)

If your not aware, pub.dev is actually written in Dart but not Flutter and is fully open source.

We could have started with the pub.dev but we wanted to deliver a Single Page App (SPA), which pub.dev is not.

What about replacing the front end of pub.dev with a Flutter interface?

My brother and I are both Java developers but we also had a decent set of Flutter skills and Flutter's web port look reasonable, dispite some community concerns around scroll performance and SEO.

__So why not Flutter?__

# Client/Server

So here is the problem with Flutter web, its not that its scroll performance is slow or even the SEO, the problem is that Flutter is client/server.

To build a web application with Flutter, you need to build:
* the web UI
* front end security layer
* a caching layer
* idempotence (so retries due to comms errors don't create duplicated data)
* a communiations layer
* backend security layer
* backend server

Hang on, you say; Every web framework is client/server, React, Angular, all of them.

Well yes, but no.

For the last 10 years I've been working with a Java framework called Vaadin.


Vaadin is a stateful web application framework, that lets you build performant SPA web applications using server side code only.

The OnePub site is written in Java and contains probably less than two dozen lines of hand written Javascript.

Perhaps a little example will help make this clearer:

```java
// register a route
@Route("User")
class UserPage implements View {

    // when the user enters the route
    void onEnter() {
        // add a layout to the page
        var layout = new VerticalLayout();
        this.add(layout);

        // add a button to the layout
        var addMe = new Button();
        layout.add(addMe);

        // add a click listener to the button
        addMe.addClickListener((event) {
            // when the user clicks the button
            // get a db connection from the caching, connection pool
            try (var db = new EntityManager())
            {
                // add a user to the db.
                var user = new User("Brett", "Sutton");
                db.persist(user);
                // show the user added confirmation page
                UI.navigateTo(AddedConfirmationPage.class).setUser(user);
            }
        });
    }
}

```

There is no hidden code here, the EntityManager connects to a local MySQL db and the rest of the code is provided by the framework.

There is no separate Web UI and backend server, they are one and the same.

There is no communications layer, because the Vaadin framework does all of the plumbing to display a button and send an event back to our Java code.

We don't have to worry about idemptoence as the only 'over the wire' communication is to the DB and all actions are transationed so if the connection fails the transaction is rolled back (the db does this, not us).

When using a framework like Vaadin, you only have to build two thing:

* a web application
* security layer

There  is no frontend and backend, there is just the web application.

You can still build fancy javascript widgets and wire them into Vaadin, you just don't normally need to.

You do loose easy access to fancy page transitions but we really didn't see that as a requirement.


# it's the productivity, stupid
If two technologies can both deliver the same set of requirements, then the tie breaker is developer productivity.


When comparing Vaadin to Flutter, we remove five layers from the stack.

In the last three years I've been involved in building a crazy Dart/Flutter application and a Java/Vaadin application.

My estimate is that we are at least twice as productive building with Vaadin.

Flutter probably has a better 'out of the box' set of widgets but we had little need for anything fancy.

The accordions we built for the Watch list and the package filters were built with Java and some CSS.

We had a web developer working to making CSS improvements for about 8 weeks - a lot of this was resizing so the web app worked on mobile. You probably wouldn't need this resource if you were using Flutter.

# what about backend Dart?

We did originally build the first version of our repository server in Dart (because I love Dart).

In the end we had to move the code to Java. This wasn't due to any inherint flaw in Dart, but was simply an issue of database cache coherency and duplication of code.

Both the Dart and Java code had to access a common set of database tables.  Doing this in both Dart and Java meant that we had to have duplicate Entity/Dao classes in both languages.  We did do this originally and it was probably going to be fine but the duplication of work didn't make us happy.

The real death of the Dart server came from cache coherency between the Dart and Java code.

To ensure our code is peformant, we run an in application  database cache. In Java the db persistance layer (we use eclipse link) provides this for us.

In Dart we wrote our own [Simple MySQL ORM](https://onepub.dev/packages/simple_mysql_orm) with a simple caching mechanism.

The problem is that we now have two caches being updated independantly. This means that a cache can return stale data to the application. This simply wasn't acceptable. 
We could have implemented an external cache, but this is less performant and you add another point of failure.

So dispite my protests we bit the bullet and re-implemented the dart repository in Java (sigh).

Never do something once, if there is a chance to do it twice.

## documentation server

When you upload a private package we automatically generate dart documentation for this.

We wrapped the dart doc library in a dart cli app that was able to spawn multiple isolates to parallize the generation process and drop the whole thing in a Docker container.

Problem solved.

Well no.  As we also wanted to provide api documentation for public packages we needed our process to also generate documentation for all 30,000 public packages and the associated 250,000 versions. 

We unboxed a fresh set of Napkins and did some maths and this seemed doable (although the ink smudged, so not actually certain). It would probably take a number of weeks to generate the documentation but this was a once off process and we were confident we could easily keep up with any new packages/version as they were published.

So we spooled up a terabyte of disk and started the dart documentor. 

Job done.

Well we thought it was done, until we ran out of disk.

This is when we discovered that we had packages where the documentation for a single we generating 23GB of files. 

That isn't a typo, 23GB of files for one version of one package. We had a single package consuming half a terrabyte of disk.

It turns out, that if you declare a static const, it gets its own dart doc page. That dart doc page includes the left hand and right hand tables of content, the result being an exponential growth in in the size of the generated doc.

One new box of napkins later, our revised maths now suggeted that we were going to need 400+ terrabytes of disk to host the entirety of pub.dev.

That simply wasn't going to be sustainable. Argh!!!!!

Take a deep breath, Plan B it is then.  

We would generated dart doc for all private packages but we would iframing the pub.dev documetation.

But of course it was never going to be that simple.

To provide an equivalent experience we had to ensure that any page links within the iframed dart doc didn't flip the user back into pub.dev. This involved dynamically replacing links in the iframed pages as we rendered.

We also wanted to be good citizens, so rather than repeatedly pulling pages from pub.dev we needed to provide a caching mechanism for documentation pages.  

OK, so now it was job done.

## the mini game

TODO: section on dart doc needs to be merged.

As with any development all too often you end up going down a rabbit hole trying to solve a problem.

Our mini game was dart documenation. So at some point in the process we decieded we wanted to keep a copy of the entire pub.dev api documentation on our system. This came about from a couple of features we desired.

TODO: this is a repeat

The first was the search experience. We were essentially providing our users with a search interface which mimiced pub.dev but still required our users to switch between pub.dev and OnePub to search.
By having a complete replica of pub.dev in our db we could give our users a better search experience and later allow us to add value added services to the public packckages.

You can already see this in that we allow you to watch public packages to recieve notifications when a new version was published as welll as our support for package discussions.

So where is that box of napkins?

pub.dev has > 30,000 packages with a total of 250,0000 versions.

On a typical day, 30 brand new packages are uploaded to pub.dev and around 270 new versions.

The average size of a tarred version is ~ 5MB, so that yields about 840GB of storage growing at about 1.35GB per day or 400GB per year.

So that looks manageable.

But here is the kicker, we forgot to include, or rather just ignored the storage for the dart documentation. After all how large could it be?

Well it wasn't goint go be ignored for long.

We first built a service to replicate the pub.dev data to our test system ( we have been very careful to manage this data to avoid having to do it again ).

This process took about 3 days. to complete.

As the replication ran we spooled up our dart documentation generation service with the intent to generate the doc for every public package (and every version) from scratch.

It didn't take very long for the documentation server to come to a screaming halt.

We had assumed, without actually checking, that the documentation for a package would be a few hundred kilobytes.

Boy were we wrong.

It took no time at all for us to discover a single package that generated a wopping 23GB of documentation.

Let me say that again, one version, of one package, 23GB. 
No that's not a typo, I mean GigaByte not Megabyte.

What the hell was going wrong here?

Well it turns out that each document page has a left and right TOC. These TOCs are generated for every page. Now when you combine this with the fact that every public constant gets its own page, if a package has a lot of contants then the amount of storage goes through the roof.

The dart devs are looking at the issue (they were as shocked as we were).

So our idea of storing doco locally was scuttled. 

> Napkin in hand; 
>
> my tears mixed with  maths
>
> ink seeps outside the lines.
>
> Fractal patterns evolve
>
> to revelations in code.
>
> A fresh box of napkins
>
> and the dilemma is solved.

Plan B, fortunately, worked fine. We are now iframing the dart dooc with a local cache for frequently accessed pages.




# its (not) a monolithic disaster

Micro services are currenlty all the rage, and scalability was a serious concern, as we were looking to be able to handle 5000 concurrent users.

So when designing our system, did we consider microservices.

For about 10 seconds.

The reality is that the benefits of micro-services are oversold and the costs are ignored.

OnePub is implemented as a monolithic Java application and the vast majority of you reading this should be doing the same.

## microservice - another name for client/server
Microservices push you back into the realm of a client/server architecture, and as I believe I've highlighted above, client/server is expensive to build.

With microservices everything becomes client/server, as you often end up with microservices calling other microservices.

If you are trying to launch a startup 'time to market' is critical. 

## microservices - a cleaner architecture

There is an argument that microservices provide a cleaner architecture as they force us to disentagle our code.

Well you don't need to be forced, you can just choose to do it. And even if you get it wrong sometimes, its usually not that hard to fix.

## microservices - the scalability myth

So there is a reasonable argument that microservices are easier to scale than a monolithic application.

The problem with this argument is that most of us don't need that level of scaling.

TODO: feels wordy

Our performance analysis of OnePub suggest that we can server 7200 concurrent users out of a single 32 core server, this equates to about 3.2 million registered users.

Let's first make certain we all understand what I mean by a concurrent user.

With OnePub we typically see an average user vist around 8 pages across 2-3 minutes.

With a 16GB/4 core server it takes around 100ms of server CPU time to serve a page. So in 3 minutes a single user consumes around 800ms of server time.

Using the following metrics:
* Minutes: 3
* Seconds in a minute: 60
* Cores: 4
* Pages per second: 10 (per core)
* Pages per site visit: 8

We see that in three minutes we can theoretically serve:
3 * 60 * 4 * 10 = 7200 page requests

Divide this by 8 means we can handle 900 users per three minute interval.

There will be a fall in performance under heavly load, but this is on a system on which we have still done minimal optimisation.

So, back of the napkin maths says, that a 32 core system can handle 7200 concurrent users.

Now consider how often a user visits our site per day.

Our current estimates suggest at most 3 times per day (this is likely to be a vast over-estimation in the long run).

So in 24 hours ( our customers are spread across the world so load will be somewhat evenly spread ) we can handle 480, 3 minutes segments which gives us:

480 * 7200 = 3.2M active users per day.

Lets assume that I'm out by an two order of magnitude, we can still service 32,000 active users on a single server.

And of course, 32 cores is hardly the upper limit on a server. Last time I looked, I believe that Google were offering servers with 196 cores and terrabytes of memory.

Remember, hardware is almost always cheaper than developers. So we look to scale our hardware before we scale our team.

## scaling a monolithic system

So we have established that a monolithic system on a single server can provide a fair amount of scale.

But what do we do if we need to scale further?

The most common cause of a bottle neck in throughput is the database.

Simply moving our database onto a separate server is likely to increase throughput by 50% at the cost of higher latency.

Both Google and AWS are now offering scalable 'cloud SQL' services or you can roll your own.

### create microservices
Yes, I know I said to not create microservices, but there is a point where they are useful.

We expect, that if we get to the point of needing microservices, then we will have  the revenue to support their development.

Carving a portion of code out of a monlithic serivces into a micro service is usually not that hard.

In the meantime, we have saved money at a point in time when we don't have much and we have reduced our time to market by an estimated 6 months.



# lessons to be learnt

TODO not very satisiying

> Build it and they will come - Field of Dreams.

Using a single language across a project is theoretically the correct, answer as it provide a massive productivity boost. 

However, its not not the only consideration as frameworks can play a larger part in your teams productivity.

Leaning on the languages/frameworks that you know will mostly yield a short term dividend but you also need
to look to the long term maintenance of your code base.

If you have to go cross language then mixing Java and Dart works well as the languages are very similar so moving
between different parts of the project has been fairly easy.

Senior developers (7+ years exp) are cheaper than junior developers.

Always ensure that you have a least one 'guru' per  language you are working with.

Unless you work for facebook, build your server as a monolithic application as you can
always split out micro services as you go.

If your are building a large project then select a strong typed language. 
* Refactoring is a daily process and typed languages offer  better refactoring
* Typed languages move errors from runtime to compile time this will save you dollars.


A fresh box of napkins

Maths bleeding because of my tears

I sit sobbing; napkin in hand
my tears mixed with  maths
ink seeps outside the lines
fractal hallucinations evolve
to revelations in code (line) (do come)
a fresh box of napkins
and the problem is solved


napkin in hand; 
my tears mixed with  maths
ink seeps outside the lines
fractal hallucinations evolve
to revelations in code (line) (do come)
a fresh box of napkins
and the problem is solved





and the problem resolved


the solution 

and the problem eluded


tears flow down my face

plan B is revealed

plan B is travelled

a new path is travelled

