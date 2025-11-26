# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib '.';
use t::TestLRUCache;

repeat_each(2);

plan tests => repeat_each() * (15 * 3);

log_level('info');
no_long_string();
run_tests();

__DATA__

=== TEST 1: sanity
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5, { ratio = 0.6 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("a", "a", 0.1)
            c:set("b", "b", 0.2)

            ngx.sleep(0.15)  -- expire "a"

            c:set("c", "c", 0.3)  -- trigger evict 

            local v = c:get("a")
            ngx.say("a: ", v)
        }
    }
--- response_body
a: nil



=== TEST 2: avoid evicting the latest set item
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5, { ratio = 0.6 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end
            c:set("a", "a", 3)
            c:set("b", "b", 2)
            c:set("c", "c", 1)  -- trigger evict
            local v = c:get("c")
            ngx.say("c: ", v)
        }
    }
--- response_body
c: c



=== TEST 3: bad ratio
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5, { ratio = 1.5 })
            if not c then
                ngx.say("init failed: ", err)
            end

            local c, err = lrucache.new(5, { ratio = -0.5 })
            if not c then
                ngx.say("init failed: ", err)
            end

            local c, err = lrucache.new(5, { ratio = -0.1 })
            if not c then
                ngx.say("init failed: ", err)
            end

            local c, err = lrucache.new(5, { ratio = 0.0001 })
            if not c then
                ngx.say("init failed: ", err)
            end
        }
    }
--- response_body
init failed: ratio must be -1 or between [0, 1]
init failed: ratio must be -1 or between [0, 1]
init failed: ratio must be -1 or between [0, 1]
init failed: max 2 decimal places



=== TEST 3a: new valid ratios
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            
            -- ratio = 0 (always trigger)
            local c, err = lrucache.new(5, { ratio = 0 })
            if not c then
                ngx.say("ratio 0 failed: ", err)
            else
                ngx.say("ratio 0 success")
            end

            -- ratio = 1 (trigger when full)
            local c, err = lrucache.new(5, { ratio = 1 })
            if not c then
                ngx.say("ratio 1 failed: ", err)
            else
                ngx.say("ratio 1 success")
            end

            -- ratio = -1 (disabled)
            local c, err = lrucache.new(5, { ratio = -1 })
            if not c then
                ngx.say("ratio -1 failed: ", err)
            else
                ngx.say("ratio -1 success")
            end
        }
    }
--- response_body
ratio 0 success
ratio 1 success
ratio -1 success



=== TEST 4: size * ratio < 1, use a as the threshold_items
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(10, { ratio = 0.09 })
            if not c then
                ngx.say("init failed: ", err)
            else
                ngx.say("init success")
            end

            ngx.say("threshold_items: ", c.threshold_items)
        }
    }
--- response_body
init success
threshold_items: 1



=== TEST 5: good ratio with 1 or 2 decimal places
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5, { ratio = 0.5 })
            if not c then
                ngx.say("init failed: ", err)
            else
                ngx.say("init success with ratio 0.5")
            end
            local c, err = lrucache.new(5, { ratio = 0.25 })
            if not c then
                ngx.say("init failed: ", err)
            else
                ngx.say("init success with ratio 0.25")
            end
        }
    }
--- response_body
init success with ratio 0.5
init success with ratio 0.25



=== TEST 6: no set ttl, no evict of the latest set item
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5, { ratio = 0.6 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("a", "a")
            c:set("b", "b")
            c:set("c", "c")  -- trigger evict
             
            local v_b = c:get("b")
            ngx.say("b: ", v_b)

            local v_a = c:get("a")
            ngx.say("a: ", v_a)

            -- get c, should not be evicted
            local v_c = c:get("c")
            ngx.say("c: ", v_c)
        }
    }
--- response_body
b: b
a: a
c: c



=== TEST 7: same ttl for all items
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5, { ratio = 0.6 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("a", "a", 0.1)
            c:set("b", "b", 0.1)

            ngx.sleep(0.15)                           -- expire "a" and "b"

            c:set("c", "c", 1)                       -- trigger evict
            -- "b" should be evicted, in cache_queue: c->b->a
            -- "c" is the latest set item, should not be evicted 
                
            -- get b, move b to the head of cache_queue: b->c->a
            local v_b, expired_v_b = c:get("b")
            ngx.say("b: ", v_b)                      -- b has been expired
            ngx.say("expired b: ", expired_v_b) -- b has not been evicted
            -- get a, move a to the head of cache_queue: a->b->c
            local v_a, expired_v_a = c:get("a")
            ngx.say("a: ", v_a)
            ngx.say("expired a: ", expired_v_a)      -- a has been evicted
        }
    }
--- response_body
b: nil
expired b: b
a: nil
expired a: nil



=== TEST 8: the queue move-to-head on get() (tail stays cold nodes)
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5, { ratio = 0.6 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("a", "a", 0.1)
            c:set("b", "b", 0.1) -- cache_queue: b->a
            c:get("a")  -- move a to head, cache_queue: a->b

            ngx.sleep(0.15)  -- expire "a" and "b"

            c:set("c", "c", 3)  -- trigger evict
            -- "b" should be evicted, in cache_queue: c->a->b
            -- "c" is the latest set item, should not be evicted
            local _, expired_v_b = c:get("b")
            ngx.say("b: ", expired_v_b)
            local _, expired_v_a = c:get("a")
            ngx.say("a: ", expired_v_a)
        }
    }
--- response_body
b: nil
a: a



=== TEST 9: ratio scan rotates non-expiring nodes to reach expired ones
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(7, { ratio = 0.6 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("a", "a")
            c:set("b", "b")
            c:set("c", "c")
            c:set("d", "d")
            c:set("e", "e")

            c:set("f", "f", 0.1)  -- initial scan does not reach "f"
            ngx.sleep(0.2)        -- expire "f"

            c:set("g", "g")       -- scan should now evict expired "f"

            local v_f = c:get("f")
            ngx.say("f: ", v_f)

            local v_a = c:get("a")
            ngx.say("a: ", v_a)

            local v_g = c:get("g")
            ngx.say("g: ", v_g)
        }
    }
--- response_body
f: nil
a: a
g: g



=== TEST 10: no ratio, value can still be read after expired
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5)
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("a", "a", 0.1)

            ngx.sleep(0.15)  -- expire "a"

            local _, v = c:get("a")
            ngx.say("a: ", v)
        }
    }
--- response_body
a: a


=== TEST 11: scavenge API
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5)
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("a", "a", 0.1)
            c:set("b", "b", 30)
            c:set("c", "c", 0.3)

            ngx.sleep(0.15)  -- expire "a"

            local evicted_key = c:scavenge()
            ngx.say("evicted: ", evicted_key)

            local v_a, stale = c:get("a")
            ngx.say("a: ", v_a)
            ngx.say("stale a: ", stale)

            local v_b = c:get("b")
            ngx.say("b: ", v_b)
            
            local v_c = c:get("c")
            ngx.say("c: ", v_c)
            
            -- Call scavenge again, nothing to evict from the last few items
            local evicted_key_2 = c:scavenge()
            ngx.say("evicted again: ", evicted_key_2)
        }
    }
--- response_body
evicted: a
a: nil
stale a: nil
b: b
c: c
evicted again: nil



=== TEST 12: ratio = -1 disables proactive eviction
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(3, { ratio = -1 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            -- Fill the cache to capacity
            c:set("a", "val_a")
            c:set("b", "val_b")
            c:set("c", "val_c")
            ngx.say("count after 3 sets: ", c:count())

            -- Set a 4th item. With ratio = -1, only LRU eviction should happen when full.
            -- "a" should be evicted.
            c:set("d", "val_d")
            ngx.say("count after 4 sets: ", c:count())

            local v_a = c:get("a")
            local v_b = c:get("b")
            local v_c = c:get("c")
            local v_d = c:get("d")

            ngx.say("a: ", v_a)
            ngx.say("b: ", v_b)
            ngx.say("c: ", v_c)
            ngx.say("d: ", v_d)
        }
    }
--- response_body
count after 3 sets: 3
count after 4 sets: 3
a: nil
b: val_b
c: val_c
d: val_d



=== TEST 13: ratio = 0 always triggers scavenge
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(5, { ratio = 0 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("e1", "val_e1", 0.1) -- Expired item
            ngx.sleep(0.15)
            c:set("a", "val_a") -- This set should trigger scavenge

            local v_e1, stale_v_el = c:get("e1")
            local v_a = c:get("a")

            ngx.say("e1: ", v_e1, ", stale e1: ", stale_v_el)
            ngx.say("a: ", v_a)
            ngx.say("count: ", c:count())
        }
    }
--- response_body
e1: nil, stale e1: nil
a: val_a
count: 1



=== TEST 14: ratio = 1 triggers scavenge when full
--- config
    location = /t {
        content_by_lua_block {
            local lrucache = require "resty.lrucache"
            local c, err = lrucache.new(3, { ratio = 1 })
            if not c then
                ngx.say("init failed: ", err)
                return
            end

            c:set("a", "val_a")
            c:set("b", "val_b")
            ngx.say("count before full: ", c:count())

            c:set("c_exp", "val_c_exp", 0.1) 
            ngx.sleep(0.15)
            
            -- Move c_exp and b to head so 'a' becomes the LRU victim
            c:get("c_exp") 
            c:get("b")
            
            c:set("d", "val_d") 

            -- Expectation:
            -- 1. LRU evicts 'a' (tail).
            -- 2. Scavenge removes 'c_exp' (expired).
            -- 3. Remaining: 'b', 'd'.

            local v_a, stale_v_a = c:get("a")
            local v_b = c:get("b")
            local v_c_exp, stale_v_c_exp = c:get("c_exp")
            local v_d = c:get("d")

            ngx.say("count after full: ", c:count())
            ngx.say("a: ", v_a, ", stale a: ", stale_v_a)
            ngx.say("b: ", v_b)
            ngx.say("c_exp: ", v_c_exp, ", stale c_exp: ", stale_v_c_exp)
            ngx.say("d: ", v_d)
        }
    }
--- response_body
count before full: 2
count after full: 2
a: nil, stale a: nil
b: val_b
c_exp: nil, stale c_exp: nil
d: val_d
