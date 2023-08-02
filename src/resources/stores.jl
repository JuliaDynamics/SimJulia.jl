struct StorePutKey{N, T<:Number} <: ResourceKey
  id :: UInt
  item :: N
  priority :: T
end

struct StoreGetKey{T<:Number} <: ResourceKey
  id :: UInt
  filter :: Function
  priority :: T
end

"""
    Store{T}(env::Environment; capacity::UInt=typemax(UInt))

A store is a resource that can hold a number of items of type `T`. It is similar to a `Base.Channel` with a finite capacity ([`put!`](@ref) blocks after reaching capacity).
The [`put!`](@ref) and [`take!`](@ref) functions are a convenient way to interact with such a "channel" in a way mostly compatible with other discrete event and concurrency frameworks.

See [`Container`](@ref) for a more lock-like resource.

Think of `Resource` and `Container` as locks and of `Store` as channels. They block only if empty (on taking) or full (on storing).
"""
mutable struct Store{N, T<:Number} <: AbstractResource
  env :: Environment
  capacity :: UInt
  load :: UInt
  items :: Dict{N, UInt}
  seid :: UInt
  put_queue :: DataStructures.PriorityQueue{Put, StorePutKey{N, T}}
  get_queue :: DataStructures.PriorityQueue{Get, StoreGetKey{T}}
  function Store{N, T}(env::Environment; capacity::UInt=typemax(UInt)) where {N, T<:Number}
    new(env, capacity, zero(UInt), Dict{N, UInt}(), zero(UInt), DataStructures.PriorityQueue{Put, StorePutKey{N, T}}(), DataStructures.PriorityQueue{Get, StoreGetKey{T}}())
  end
end

function Store{N}(env::Environment; capacity::UInt=typemax(UInt)) where {N}
  Store{N, Int}(env; capacity)
end    
    
"""
    put!(sto::Store, item::T)

Put an item into the store. Returns the put event, blocking if the store is full.
"""
function put!(sto::Store{N, T}, item::N; priority::T=zero(T)) where {N, T<:Number}
  put_ev = Put(sto.env)
  sto.put_queue[put_ev] = StorePutKey{N, T}(sto.seid+=one(UInt), item, priority)
  @callback trigger_get(put_ev, sto)
  trigger_put(put_ev, sto)
  put_ev
end

get_any_item(::T) where T = true

function get(sto::Store{N, T}, filter::Function=get_any_item; priority::T=zero(T)) where {N, T<:Number}
  get_ev = Get(sto.env)
  sto.get_queue[get_ev] = StoreGetKey(sto.seid+=one(UInt), filter, priority)
  @callback trigger_put(get_ev, sto)
  trigger_get(get_ev, sto)
  get_ev
end

function do_put(sto::Store{N, T}, put_ev::Put, key::StorePutKey{N, T}) where {N, T<:Number}
  if sto.load < sto.capacity
    sto.load += one(UInt)
    sto.items[key.item] = get(sto.items, key.item, zero(UInt)) + one(UInt)
    schedule(put_ev)
  end
  false
end

function do_get(sto::Store{N, T}, get_ev::Get, key::StoreGetKey{T}) where {N, T<:Number}
  for (item, number) in sto.items
    if key.filter(item)
      sto.load -= one(UInt)
      if number === one(UInt)
        delete!(sto.items, item)
      else
        sto.items[item] = number - one(UInt)
      end
      schedule(get_ev; value=item)
      break
    end
  end
  true
end

"""
    isready(::Store)

Returns `true` if the store is not empty, similarly to the meaning of `isready` for `Base.Channel`.

```jldoctest
julia> sim = Simulation(); store = Store{Symbol}(sim); isready(store)
false

julia> put!(store, :message); isready(store)
true
```
"""
isready(sto::Store) = sto.load > 0

"""
    islocked(::Store)

Returns `true` if the store is full, similarly to the meaning of `islocked` for `Base.ReentrantLock`.

```jldoctest
julia> sim = Simulation(); store = Store{Symbol}(sim; capacity=2); islocked(store)
false

julia> put!(store, :message); islocked(store)
false

julia> put!(store, :another_message); islocked(store)
true
```
"""
islocked(sto::Store) = sto.load==sto.capacity

unlock(::Store) = error("There is no well defined way to \"unlock\" a Store without taking an element out of it. Instead of attempting `unlock` consider using `take!(::Store)` or use a `Resource` instead of a `Store`. Think of `Resource` and `Container` as locks and of `Store` as channels. They block only if empty (on taking) or full (on storing).")
lock(::Store) = error("There is no well defined way to \"lock\" a Store without storing an element in it. Instead of attempting `lock` consider using `put!(::Store, ...)` or use a `Resource` instead of a `Store`. Think of `Resource` and `Container` as locks and of `Store` as channels. They block only if empty (on taking) or full (on storing).")
trylock(::Store) = error("There is no well defined way to \"lock\" a Store without storing an element in it. Instead of attempting `lock` consider using `put!(::Store, ...)` or use a `Resource` instead of a `Store`. Think of `Resource` and `Container` as locks and of `Store` as channels. They block only if empty (on taking) or full (on storing).")
request(::Store) = error("There is no well defined way to \"request\" a Store without storing an element in it. Instead of attempting `request` consider using `put!(::Store, ...)` or use a `Resource` instead of a `Store`. Think of `Resource` and `Container` as locks and of `Store` as channels. They block only if empty (on taking) or full (on storing).")
tryrequest(::Store) = error("There is no well defined way to \"request\" a Store without storing an element in it. Instead of attempting `request` consider using `put!(::Store, ...)` or use a `Resource` instead of a `Store`. Think of `Resource` and `Container` as locks and of `Store` as channels. They block only if empty (on taking) or full (on storing).")

"""
    take!(::Store)

An alias for `get(::Store)` for easier interoperability with the `Base.Channel` interface. Blocks if the store is empty.
"""
take!(sto::Store, filter::Function=get_any_item; priority::Int=0) = get(sto, filter; priority)
