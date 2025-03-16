package Scratch
import "core:mem"
import "core:mem/virtual"

//This project makes heavy use of temporary scratch arena allocators.
//Whenever a short lived allocation is required e.g. for string formatting or returning an unkown amount of objects from a procedure (via slice),
//a scratch arena should be used.
//A single arena might be enough for most use cases but with 2 we gain the ability of using a scratch arena in a procedure that gets another scratch arena
//already passed in as a parameter.
//'Init' must be called from each thread that want to use scratch arenas.
//For more information I recommend this article: https://www.rfleury.com/p/untangling-lifetimes-the-arena-allocator
@(thread_local)
Arenas: [2]virtual.Arena

Init :: proc() {
	for &arena in Arenas {
    _ = virtual.arena_init_growing(&arena, mem.Kilobyte * 64)
	}
}

@(private)
GetArena :: proc(conflicts : []^virtual.Arena = {}) -> ^virtual.Arena {
  if len(conflicts) == 0 do return &Arenas[0]
  
  for &arena in Arenas {
    for conflict in conflicts {
      if &arena != conflict do return &arena
    } 
  }

  panic("No conflict free scratch arena available")
}

//'conflicts' must contain arenas that are already in use for the current scope.
//Usually this means, whenever an arena is passed into a procedure, it must not be used for other
//temporary allocations during the execution of the prcoedure. By adding it to 'conflicts'
//you ensure that you don't get the same arena twice.
Begin :: proc(conflicts : []^virtual.Arena = {}) -> virtual.Arena_Temp {
  return virtual.arena_temp_begin(GetArena(conflicts))
}

End :: proc(temp : virtual.Arena_Temp) {
  virtual.arena_temp_end(temp)
}