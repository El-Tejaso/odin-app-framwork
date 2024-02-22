
TODO: Upcoming multithreading update

I plan on updating this framework to be a whole lot faster, so that I can poll for inputs at 1000zh like Osu! Lazer.
After all, the whole point of this framework was so that I could make an osu!-like clone from scratch.
There are some other benefits from having a second thread, like async resource loading, and rendering while we are
resizing the window.

I think I will do this simply by moving the opengl context to the rendering thread.
The main thread can do all the file IO, but all the opengl calls will still be done by the rendering thread.
If I am able to upload all my meshes beforehand, I should be able to keep my update code fairly efficient, so that the rendering thread can do the heavy lifting, and my render thread won't have to lock some resource being updated by the update thread. Actually, if my update thread is updating something, won't it have to wait for the render thread to finish up with rendering? Shieet. 

```

render :: proc() {
    sleep_for_60fps();
    aquire(scene)
  
    for obj in scene: 
      render_mesh(obj.transform, obj.materials, obj.mesh)
}

update :: proc() {
    sleep_for_1000fps();
    aquire(scene)

  for obj in scene: 
    get_user_input_and_update_object(obj)
}

```

Now what? every 1/60 seconds, the update thread will freeze for a bit, which is not ideal.
I suppose in a rhythm game, we would just set some flag = true or push some element to an input buffer, and then
the render thread can take care of making all the updates. 
In fact, if the render thread also does the updating, then we should be good.
So really, we need some more mechanisms here. Maybe the solution is to just perform the update on the rendering thread itself? not too sure.

I really cant think of an efficient way to sync those threads, esp when update needs to run at 1000hz while rendering a frame may take a LOT longer. 
The idea I have is for the rendering thread to lock and unlock the render state for as little time as possible, and then spend the rest of the time rendering. Something like:

```


render :: proc() {
    sleep_for_60fps();
    // this should be extremely fast, ideally faster than the time it takes to poll input.
    // it will still cause some sort of disturbance, but hopefully not as much. 
    copy_to_buff(scene)
  
    for obj in scene_copy: 
      // this might take a while
      render_mesh(obj.transform, obj.materials, obj.mesh)
}

update :: proc() {
    sleep_for_1000fps();
    aquire(scene)

  for obj in scene: 
    get_user_input_and_update_object(obj)
}


```

The other idea is to push all the inputs onto the queue.
Then the render thread will handle the fixed updating, as well as the frame rendering. 

```
render :: proc() {
    run_fixed_update(inputs);
    sleep_for_60fps();
  
    for obj in scene: 
      // this might take a while
      render_mesh(obj.transform, obj.materials, obj.mesh)
}

update :: proc() {
  for input in af.inputs: 
    queue_inputs(&inputs, input) 
}

```

The fixed update code will have some abstractions, i.e the code to check if a key is down will also need to be passed the current time, so that we know how many inputs to pop from the input queue.
It also needs to handle edge-cases, like lag spikes.
A bit too complicated, I think.
I will try the simple copying approach, and see what happens.
However, I will need to significantly simplify my rendering to be able to do this. 
I will have to start rendering meshes only, and basically stop doing this whole immediate mode thing.
Rather than pushing a massive list of vertices and indices to the GPU with every frame, I would prefer that I push
a large list of mesh ids and transform matrices, and render them all in batch somehow.
This should make the copy_to_render_thread fn work much faster as well, hopefully.
I would also need to be a lot less reliant on rects. Most UI should be images anyway.
Some procedural mesh stuff where I update a mesh on every frame may be harder to do, though.
I would end up just uploading a lot of verts from my update thread to my render thread and there will be very little benefit to separating the input and render threads. The whole point of which was to get accurate timings for key presses for my rhythm game clone. 

```

input {
  KeyCode , TimeStampDelta
}

pressed = false;

for i in inputs {
  if i.timeStampDelta > fixedTimeSinceLastFrame {
    break;
  }

  if i == .key {
    if pressed {
      pressed = true;
    } else if released {
      released = true;
    }
  }
}

return pressed;

```

Not sure how to do this. 
Alternatively:
- don't lock the other array. Allow multiple threads to access the data, and that it wont be changing much very often. 
- probably not a good thing to do.
- really, this should be a case by case decision per game. Most games don't need 1000hz input, and the rhythm games that do won't need complex state sharing between the render and update threads. Their animations can literally all be triggered with a few boolean flags.
- I suppose we can have something like:


```

update_thread :: proc() {
  init framework, opengl()
  relinquish gl context();
  start the render thread();

  closed = false
  while true:
    sleep_for_1000fps();
    poll window events.
    if escape was pressed, break;
    update the game/physics/scene state.

  closed = true
}

render_thread :: proc() {
  make gl context current();
  while !closed:
    lock the state();
    // I hope this is fast...
    copy over the data that we need to do rendering();
    unlock the state();

    render the scene();
}


```

In this sense, game updates are seperated from rendering. And we also get a few benefits from being multithreaded, like
loading things with a loading spinner, and being able to rerender while resizing the window.
The drawback is that the code may be a bit more complicated, and we have to copy over some state before we can render anything...;

How would I wrap this all in a neat API that simplifies things while also giving a lot of power?
I would rather not make people have to specify a million callbacks to all the areas they my want to run their code, like a JavaScript library.

```

main() :
  af.init();
  defer af.uninit();

  // this call is optional, and moves the gl context to this function.
  af.start_render_thread(render_thread)

  while !af.prepare_frame() {
      // draw frame
  }

```

Right now, I have a af.run_main_loop function. This is mainly so that I can rerender my program while I'm resizing it.
It isn't true rerendering like a second thread, because the rerendering still blocks when I'm holding down the OS resize-handles without actually moving them.

I could potentially deprecate this, and then tell people they need to just render their thing in a second thread if they want that functionality.
Now, their code can be as simple or as complicated as they want it to be.
They can do everything in the main thread in an immediate mode way, or they can render in a second thread with the same simple code.
Except that input checking HAS to be in the main thread. So I guess it isn't as flexible as I would have thought. 
But it still gives them the following options:

- all code on main thread
- input code on main thread, rest of code on seperate thread
- input and update code on main thread, rest of code on second thread

Might need some other helpers like sleep_for_hz (&timeTracker, 60) or something.
But yeah, looks like a decent design.
Might even be worth just adding a set_resize_callback() func if I really want to just keep my UI designing tool code in the main thread and preview layout changes, without having to multithread everything...

Going to write some more code to check that the design is somewhat passing:

```

press_started: false;

render_thread():
  set_color(press_started ? red : green)
  render_rectangle_sliced(button_rect,button_sliced_texture )
  // imagine same for text rendering


update_thread():
  if mouse_over(button_rect):
    if mouse_pressed:
      press_started = true
  else:
    press_started = false

  if press_started && mouse_released:
    press_started = false
    do_action();
```

We would need two functions, like update_button(&button) and render_button(&button). 
If we had a UI tree, we would need two seperate funcs to update it and to render it. 
This is fine, I think. The last version of my framework was like this anyway, except it split the render and update functions for code aesthetic reasons rather than legitimate ones.


However, now we need to be careful.
Depending on whether or not we called start_render_thread(), we need to make sure we don't check for 
input or do any other main thread things from within the render thread.
I can't think of many ways to enforce this with the code, actually.
One way could be that the render context API calls should act on a 'renderContext' that gets passed into the render thread somehow, but then we would need a carve-out to access it for single-threaded apps.
I think if I just take care with each feature, it should be fine. 
After all, it isn't like bad code that is doing weird stuff just gets added randomly.
I am the only one writing any code here, after all.

It looks like there is one other thing to consider - some things regarding resetting the frame boundary is related to rendering, and other stuff is related to polling input.
I will have to seperate these as well. 

I'm not sure if I should have an abstraction like move_rendering_context_to_this_thread();
Maybe I could just have a `get_rendering_context()` and this internally will move the context to the thread it was called on.
This doesnt exactly work though, because in openGL, the main thread must release the context before another thread can take it.
This is tha main reason why I wanted to do start_rendering_thread().

Now, the code can look like either of these:

```

proc :: main() {
    af.init();
    defer af.deinit();
}

```

I think the input would need to be read in a producer/consumer manner on the render thread. 
I would need two APIs - 1 to query the current position, one to query the position at a particular moment in time.
Appending to the input ringbuffer might block the input if the render thread takes too long though.
I think I would have to just split the update logic from the render logic and process the input and physics update from the main thread itself. 
It might be a bit of a pain to provide a threadsafe API for the render thread to check a list of accurate input timings since the last frame. 
Not to mention that it would complicate my codebase as well as downstream codebases for no reasons.
It means that I don't really have any flexibility though. Or it would mean that my code would look like one of these two:

```

main :: proc() {
    af.init();
    defer af.deinit();

    while af.new_rer_frame() && af.new_update_frame() {
      // simple code
      if mouse is over rectangle:
        color = highlight color 

        if mouse is clicked:
          click the button
      else 
        color = normal color

      render the button
    }
}

```

OR:


```

main :: proc() {
    af.init();
    defer af.deinit();

    // render_proc is defined elsewhere
    af.start_render_thread(render_proc)

    while af.new_update_frame() {
      // still surprisingly simple code, actually
      if mouse is over rectangle:
        color = highlight color 

        if mouse is clicked:
          click the button
      else 
        color = normal color

    }
}

render_proc :: proc() {
  while af.new_render_frame() {
      render the button
  }
}

```

Yeah I am liking this, ngl. 
Will start work on it today.