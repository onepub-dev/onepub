With the release of the OnePub beta, I thought the develop process behind
OnePub might make an interesting read, because it has certainly been in interesting ride.

This is the story of our tech startup primarily from a technical perspective.

So lets go back to the very beginning.

Our story has a few twists and turns, perhaps for you the reader, the most interesting is that 
we didn't use Flutter for our web interface, but not for the reasons that you are expecting.

But I get ahead of myself; so lets go back to the begining.

I first started using Dart sometime around the release of 2.1.

# crazy, delivers innovation
We had this crazy idea to build an entire business phone system into an app.

As web developers, with no mobile app experience, we were not keen on the idea of building a pair
of mobile apps from scratch.

## pwa
So our first thought was to build a [PWA](https://en.wikipedia.org/wiki/Progressive_web_application) designed for a mobile device.

We had a stable webstack we could re-use and delivering a mobile friendly PWA looked easy.

Problems however surfaced rather quickly. We needed access to a user's contact list, push notifications and the dial pad.

For that we were going to need an actual app.

## cordova
OK, so a simple PWA wasn't going to work, what about a hybrid system like Cordova.

This look promising until we looked at the available plugins. There was a plugin that allowed
access to contacts but it appear to be no longer supported.

## react native
Alright then, lets take a look at React Native.

The aim was to use the React Native webview to host our web app and then use react to call
into the mobile device.
I honestly don't remember the reason why we dumped React Native, but I do recall trying to
wrangle access to host mobile device from the webview and realizing that it was a complete hack. 

## flutter
So time to review the options once more. It was this moment in time that one of our System Admins
reminded us that he had suggested this framework called Flutter and that maybe we should
go back and take a look at it ( and that we should have listened to him the first time around - OK fair point ).

And this is where my Dart journey started. I should say that I like Flutter, but
that I love Dart. 

### state management
Flutter is a nice framework but the whole state management thing is a pain in the arse and is really Flutters Achilles' heel.

You only need to look a the very large no. of state managment libraries for Flutter to realize this is still an unsolved problem.

About half way through the project, one of the team suggested that we should be using BLOC. So we stopped for 4 weeks to roll BLOC into the app.

At the end of the 4 weeks we did a review of the resulting code. 

BLOC had significantly increased the lines of code, increased code complexity and moved the state logic further from the UI which made static analysis harder (with no unit test benefits over the prior implementation).

The result was that we ripped BLOC out of the code base and went back to a hodgepodge of Provider, setState and an enhanced Future Builder.  

I should note that this wasn't a trival app, having more than 50 unique screens, many of them with complex state.

## dart is a joy to behold
Dart on the other hand is a beautiful language.

For Flutter the combination of being cross platform and underpinned by a great language, leads me to 
the conclusion that Flutter will become the dominate GUI framework (dispite the state management issue).

I belive this to the extent, that with the launch of OnePub, I have bet my entire financial future on Flutter.

History will be the judge of my roll of the dice.

# dartastic revelations

Don't get me wrong, Dart does have its problems.  

It's far too easy to forget to await a function call and isolates limit performance by not allowing shared memory for items like database caches. 

The await issue is improving, with the introduction of additional lints, but we still have a way to go.

The Dart eco system, particularly on the backend, is however, still immature. It is getting better, but it is going to take time.

# new beginings

For a number of commercial reason our crazy Flutter project was cancelled but it didn't matter, I was already hooked on Dart.

I started building the [DCli console SDK for Dart](https://onepub.dev/packages/dcli) and rewote our entire production build and deployment using Dart and DCli.

I hadn't had some much fun coding in a very long time.

Over the next couple of years I published almost 40 packages to pub.dev and contributed PR's to a similar no. of projects.

It was during this journey that I realized that I needed a private repository and there really wasn't anything out there that
delivered what I thought I needed.

So December of 2021 I decided to form a new company and build one.

# intent
The first questions we needed to answer were:
* exactly what part of the eco system are we trying to fill?
* what are dart developers looking for?
* what do we think the user journey will look like?
* how do we ensure that our actions don't undermine pub.dev?
* how do we market and monetise the service?
* will and how much are developers prepared to pay for the service?

Even with the release of the Beta we still don't have all of the above answers. 

We did have a hard look at some of the existing players in the repository market (such as NPM) on the basis that if developers where paying for NPM then logically the should pay for a Dart repository.

The comparision however wasn't conclusive as each of the providers, offer other services beyond just a repository. 

We also interviewed a few external Dart developers and recieved positive feedback but that still isn't the same as having them take out their credit card to pay for a service.

> At some point a `leap of faith` was required.

The developer experience was the next big issue. Very early on the process we decieded that we wanted to closely mimic the pub.dev interface. We had two reasons for this; 1) it was a fairly well thought out interface 2) our users wouldn't need to learn how to use OnePub

The second point was really the driver behind the decision to mimic pub.dev.

## first rate experience
We also wanted to the CLI user experience to be 'native'.

As a Java/Dart developer I really hate when I get told to install Python, Ruby or some other runtime to work with Java/Dart tools.

I also hate it when I have to do a whole chunk of work to integrate the tooling into my existing process.

This meant that the OnePub CLI tooling had to be written in Dart and work with the existing Dart CLI tooling seamlessly.

Fortunately for us, with the release of Dart 2.15, Dart officially supported private repositories.

This still meant that we had a problem with pre 2.15 users which we wanted to support (big organisations are more likely to pay for our service and more likely to be using an older version of Dart).

So the question was how do we support pre 2.15 customers?

We did this exposing a replacement tool for the `dart pub` command called `opub` (if you are post 2.15 you use the standard dart pub command).

We created the opub command by back porting the `dart pub` code. Unfortunately/fortunately the dart pub code is null safe 
This actually caused us a number of problems. The dart pub code that supported private repos was writting with null safety




# commencement

Worked started on OnePub in Janurary of 2022, initially just me but eventually my brother Robert joined the project, both of us still holding down another job.

From early Janurary to mid July I worked 7 days a week on the project, doing an averaging 80 hrs a week with a single long weekend off in March.

From inception to the release of a beta, I estimate that we put in about a man year of development.




# platorm evolution
So there we were, once again at the start of product development cycle, with no net, as I had literally bet the house on it.

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

My brother and I are both Java developers but we also had a decent set of Flutter skills and Flutter's web port look reasonable dispite some concerns community concerns around scroll performance and SEO.

So why not Flutter?

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

For the last 10 years I've been working with a java framework called Vaadin.

Vaadin is a stateful ( I will come back to this ) web application framework that lets you build performant SPA web applications using server side code only.

The OnePub site is written in Java and contains probably less than two dozen lines of Javascript that we wrote as part of the development.

Perhaps a little example will help make this clearer:

```java
// register a route
@Route("User")
class UserPage implements View {

    // when the user enters the route
    void onEnter() {
        // add a layout to the view
        var layout = new VerticalLayout();
        this.add(layout);

        // add a button to the layout
        var addMe = new Button();
        layout.add(addMe);

        // add a click listener to the button
        addMe.addClickListener((event) {
            // get a db connection from the caching, connection pool
            try (var db = new EntityManager())
            {
                // add a user to the db.
                var user = new User("Brett", "Sutton");
                db.persist(user);
                Notification.show("User Added");
            }
        });
    }
}

```

There is no hidden code here, the EntityManager connects to a local MySQL db and the rest of the code is provided by the framework.

There is no separate Web UI and backend server, they are one and the same.

There is no communications layer because the Vaadin framework does all of the plumbing to display a button and send an event back to our Java code.

We don't have to worry about idemptoence as the only 'over the wire' communication is to the DB and all actions are transationed so if the connection fails the transaction is rolled back (the db does this not us).

When using a framework like Vaadin you only have to build two thing:

* a web application
* security layer

There  is no frontend and backend, there is just the web application.

You can still build fancy javascript widgets and wire them into Vaadin, you just don't normally need to.

You do loose easy access to fancy page transitions but we really didn't see that as a requirement.


# it's the productivity, stupid
If two technologies can both deliver the same set of requirements, then the tie breaker is developer productivity.


When comparing Vaadin to Flutter, we remove five layers from the stack.

In the last three years I've been involved in building a Dart/Flutter application and a Java/Vaadin application.

My estimate is that we are at least twice as productive building with Vaadin.

Flutter probably has a better 'out of the box' set of widgets but we had little need for anything fancy.

The accordions we built for the Watch list and the package filters were built with Java and some CSS.

We had a web developer working to making CSS improvements for about 8 weeks - a lot of this was resizing so the web app worked on mobile. You probably wouldn't need this resource if you were using Flutter.

# what about backend Dart?

We did originally build the first version of our repository server in Dart (because I love Dart).

In the end we had to move the code to Java. This wasn't due to any inherint flaw in Dart, but was simply an issue of database cache coherency and duplication of code.

Both the Dart and Java code had to access a common set of database tables.  Doing this in both Dart and Java meant that we had to have duplicate Entity/Dao classes in both languages.  We did do this originally and it was probably going to be fine but the duplication of work didn't make us happy.

The real death of the Dart server came from cache coherency between the Dart and Java code.

To ensure our code is peformant we run an in appliation  database cache. In Java the db persistance layer (we use eclipse link) provides this for us.

In Dart we wrote our own [Simple Mylsq ORM](https://onepub.dev/packages/simple_mysql_orm).

The problem is that we now have two caches being updated independantly. This means that a cache can return stale data to the application. This simply wasn't acceptable. 
We could have implemented and external cache, but this is less performant and you add another point of failure.

So dispite my protests we bit the bullet and re-implemented the dart repository in Java (sigh).

## documentation server


When you upload a private package we automatically generate dart documentation for this.

We originally intended to do this by spawning the `dart doc` command.

# its (not) a monolithic disaster

When designing our system, did we consider microservices.

For about 10 seconds.

The reality is that the benefits of micro-services are oversold and the costs are ignored.

OnePub is implemented as a monolithic java application and the vast majority of you reading this should be doing the same.

## microservice - another name for client/server
Microservices push you back into the realm of a client/server architecture, and as I believe I've highlighted above, client/server is expensive to build.

With microservices everything becomes client/server as you often end up with microservices calling other microservices.

If you are trying to launch a startup 'time to market' is critical. 

## microservices - a cleaner architecture

There is an argument that microservices provide a cleaner architecture as they force you to disentagle your code.

Well you don't need to be forced, you can just choose to do it. And even if you get it wrong sometimes its usually not that hard to fix.

## microservices - the scalability myth

So there is a reasonable argument that microservices are easier to scale than a monolithic application.

The problem with this argument is that most of us don't need that level of scaling.

Our performance analysis of OnePub suggest that we can server 7200 concurrent users out of a single 32 core server.

Lets first make certain we all understand what I mean by a concurrent user.

With OnePub we typically see an average user vist around 8 pages across 2-3 minutes.

With a 16GB/4 core server it takes around 100ms server time to serve a page. So in 3 minutes a single user consumes around 800ms of server time.

So in three minutes our 4 core system can theoretically serve:
Minutes: 3
Seconds in a minute: 60
Cores: 4
Pages per second: 10 (per core)
Pages per site visit: 8

So in three minutes we can theoretically serve:
3 * 60 * 4 * 10 = 7200 page requests

Divide this by 8 means we can handle 900 users per three minutes.

There will be a fall in performance under heavly load, but this is on a system on which we have still done minimal optimisation.

So back of the napkin maths says that a 32 core system can handle 7200 concurrent users.

If you now consider how ofter a user visits our site per day.

Our current estimates suggest at most 3 times per day (this is likely to be a vast over-estimation in the long run).

So in 24 hours ( our customers are spread across the world so load will be somewhat evenly spread ) we can handle 480, 3 minutes segments which gives us:

480 * 7200 = 3.2M registered users

Lets assume that I'm out by an order of magnitude, we can still service 320K users on a single server.

## scaling a monolithic system

So we have established that a monolithic system on a single server can provide a fair amount of scale.

But what do we do if we need to scale further?

The most common cause of a bottle neck in throughput is going to be your database.

32 core is hardly the upper limit on a server and there

# lessons to be learnt

Using a single language across your project is theoretically the correct answer as it provide a massive productivity boost
however, its not not the only consideration as frameworks can play a larger part in your teams productivity.

Leaning on the languages/framewors that you know will mostly yield a short term dividend but you also need
to look to the long term maintenance of your code base.

If you have to go cross language the mixing Java and Dart works well as the languages are very similar so moving
between different parts of the project has been fairly easy.

Senior developers (7+ years exp) are cheaper than junior developers.

Always ensure that you have a least one 'guru' per  language you are working with.

Unless you work for facebook, build your server as a monolithic application as you can
always split out micro services as you go.

If your are building a large project then select a strong typed language. 
* Refactoring is a daily process and typed languages offer  better refactoring
* Typed languages move errors from runtime to compile time this will save you dollars.












































