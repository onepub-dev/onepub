

### state management
``` consider removing
Flutter is a nice framework but the whole state management thing is a pain in the arse and is really Flutters Achilles' heel.

You only need to look a the very large no. of state managment libraries for Flutter to realize this is still an unsolved problem.

About half way through the project, one of the team suggested that we should be using BLOC. So we stopped for 4 weeks to roll BLOC into the app.

At the end of the 4 weeks we did a review of the resulting code. 

BLOC had significantly increased the lines of code, increased code complexity and moved the state logic further from the UI which made static analysis harder (with no unit test benefits over the prior implementation).

The result was that we ripped BLOC out of the code base and went back to a hodgepodge of Provider, setState and an enhanced Future Builder.  

I should note that this wasn't a trival app, having more than 50 unique screens, many of them with complex state.
```

## dart is a joy to behold
Dart on the other hand is a beautiful language.

For Flutter the combination of being cross platform and underpinned by a great language, leads me to 
the conclusion that Flutter will become the dominate GUI framework (dispite it's state management issues).

``` later
I belive this to the extent, that with the launch of OnePub, I have bet my entire financial future on Flutter.

History will be the judge of my roll of the dice.
```

# dartastic revelations

Don't get me wrong, Dart does have its problems.  

It's far too easy to forget to await a function call and isolates limit performance by not allowing shared memory for items like database caches. 

``` remove?
The await issue is improving, with the introduction of additional lints, but we still have a way to go.

The Dart eco system, particularly on the backend, is however, still immature. It is getting better, but it is going to take time.
```