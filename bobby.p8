pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
--https://fr.pngtree.com/free-animals-photos


--  game params
--------------------------------------
    GRAVITY = 0.3
    seed = rnd(120) srand(seed)
--

--  useful, various
----------------------------------------
    time=0
    nul = function()end  -- useful useless function
    
    local function cowrap(f)
        local coro, done = cocreate(f)
        return function(...)
            if not done then
                assert(coresume(coro, ...))
                done = costatus(coro) == 'dead'
            end
            return done
        end
    end

    --- player constants
    RIGHT = true LEFT = false
    RUNNING_R = 1 RUNNING_L = 3
    STILL = 2 CLIMBING = 7 TALKING = 9
    MOVE_DOWN = 4 MOVE_UP = 5
    IN_AIR_1 = 6 IN_AIR_2 = 8
    a_MEDIUM = 2 a_VERY_SLOW = 20
	a_SLOW = 5

    function blackline(s,x,y,h,w,d,col)
        local _col=col or 0
        for i=1,15 do pal(i,col) end
        spr(s,x-1,y,h,w,d)
        spr(s,x+1,y,h,w,d)
        spr(s,x,y-1,h,w,d)
        spr(s,x,y+1,h,w,d)
        pal()
    end
--

--  vecteurs
---------------------------------------
    vec={} vec.__index = vec
    function vec:__add(b)  return v(self.x+b.x,self.y+b.y)end
    function vec:__sub(b)  return v(self.x-b.x,self.y-b.y)end
    function vec:__div(d)  return v(self.x/d,self.y/d)end
    function vec:__mul(m)  return v(self.x*m,self.y*m) end
    function vec:__len()    return (sqrt(self.x^2+self.y^2)) end
    function vec:__peek()   return self/#self end -- normalize
    function vec:__or(m) if (#self>m) then return  @self*m else return self end end
    function vec:to_block() return {self.x\8,self.y\8} end
    function v(x,y)      return setmetatable({x=x,y=y or 0,},vec)end
--

--
    water = {}
    function addwater(x,y,dir,spd)
        w={s=0.9,x=x,y=y+rnd(1),dx= (dir and -0.8+spd.x) or 0.8+spd.x,  dy=-rnd(0.3),pat=flr(rnd(1))}
        p = {░}
        r=rnd(1)
        if(r>0.8)then p={▥}end
        w.pat = p[w.pat+1]-->>flr(rnd(2))
        w.dx += 0.3 - rnd(0.6)
        add(water,w)
    end

    function update_water()
        for w in all(water)do
            w.dy += 0.17
            w.y+=w.dy
            --w.s +=0.05
            w.x+=w.dx
            if(fget(mget(w.x\8,w.y\8),1)) then del(water,w)end
            -- todo: flowers lookup table per level 
        end
    end
    function draw_water( )
        for w in all(water)do
            --fillp(w.pat)
            circ(w.x,w.y,w.s,1)
            fillp()
        end
    end
--

-- motion functions (--> move to character class?)
---------------------------------------
    function go_left(p) 
        if(p.spd.x < p.maxspd) then p.spd.x +=0.2 end
        --p.offset = p.clop*cos(4*t()+ p.phase)
    end
    function go_right(p)
        if(p.spd.x >-p.maxspd) then p.spd.x -=0.2 end
        --p.offset = p.clop*cos(4*t()+ p.phase)
    end
    function stop(p)
        if(p.grounded) then 
            if(abs(p.spd.x)>0.5) then p.spd.x -= (p.spd.x/abs(p.spd.x))*0.3 else p.spd.x = 0 end
        else
            if(abs(p.spd.x)>0.5) then p.spd.x -= (p.spd.x/abs(p.spd.x))*0.1 else p.spd.x = 0 end
        end
        p.offset = 0
    end
    function go_down(p)
        if(p.climbing) then 
            p.spd.y = 1
            return
        end
    end
    function go_up(p)
        if(p.climbing) then 
            p.spd.y = -1
            return
        end
        if(p.grounded)then
            p.spd.y -= 3
        end

    end
--

-- classes + spawning function
---------------------------------------
    entities = {}
    inheritance = {
        ['character']='object',
        ['player']='character',
        ['something']='object'
    }

    -- todo state, anim_number, DT
    local entity_classes = {

        ['object']={ --3 objet physique
            -- required: vectors, GRAVITY, states(STILL), time,c?
            function(self)
                self:draw_sprite()
            end,nil,

            draw_sprite = function(self,do_blackline)

                local anim_list = self.sprites[self.state]
                local ox,oy =  (self.width/2 + self.bx ),   (  self.height/2 + self.by)
                blackline(anim_list[self.frame],self.pos.x - ox,self.pos.y- oy + self.offset,1,1,self.direction,1)
                spr(anim_list[self.frame],self.pos.x -ox,self.pos.y-oy + self.offset,1,1,self.direction)

            end,

            collide_floor = function(self)
                --only check for ground when falling.
                if self.spd.y<0 then return false end

                for i=-(self.width/3),(self.width/3),2 do
                    local tile = mget((self.pos.x+i)/8,(self.pos.y +self.spd.y+ (self.height/2))/8)
                    if(fget(tile,0)) then

                        self.pos.y = flr((self.pos.y+self.spd.y+(self.height/2))/8 )*8 - self.height/2
                        self.grounded = true
                        self.spd.y = 0
                        
                        return true
                    end
                end
                return false
            end,
            collide_ceiling = function(self)
                --only check for ceiling when jumping.
                if self.spd.y>0 then return false end

                for i=-(self.width/3),(self.width/3),2 do
                    local tile = mget((self.pos.x+i)/8,(self.pos.y +self.spd.y- (self.height/2))/8)
                    if(fget(tile,2)) then

                        self.pos.y = flr((self.pos.y+self.spd.y-(self.height/2))/8 )*8 +8+ (self.height)/2
                        self.spd.y = 0
                        return true

                    end
                end
                return false
            end,
            collide_walls = function(self)

                local offset = self.width/2 

                for i=-(self.height/3),(self.height/3),2 do
                    local tile = mget((self.pos.x+self.spd.x+(offset))/8,(self.pos.y+i)/8) 
                    
                    if(fget(tile,2)) then
                        --self.spd.x=0
                        self.pos.x = (flr(((self.pos.x+self.spd.x+(offset))/8))*8) - (offset)
                        self.walled = true
                        return true
                    end

                    local tile = mget((self.pos.x+self.spd.x-(offset))/8,(self.pos.y+i)/8) 
                    if(fget(tile,2)) then
                        --self.spd.x=0
                        self.pos.x = (flr(((self.pos.x+self.spd.x-(offset))/8))*8) +8+ (offset)
                        self.walled = true
                        return true
                    end
                end
                return false
            end,
            on_block = function(self,flag)
                local t1,t2,t3,t4 = 
                mget((self.pos.x-self.width/2)/8,(self.pos.y-self.height/2)/8),
                mget((self.pos.x+self.width/2)/8,(self.pos.y-self.height/2)/8),
                mget((self.pos.x-self.width/2)/8,(self.pos.y+self.height/2)/8),
                mget((self.pos.x+self.width/2)/8,(self.pos.y+self.height/2)/8)

                if(fget(t1) & fget(t2) & fget(t3) & fget(t4) & flag !=0 ) then return true end

                return false
            end,
            fall = function(self) 
                if(self.spd.y<self.maxyspd) then
                    self.spd.y += GRAVITY 
                end
            end,
            collide = function(self) -- wraps collision checks on world map
                if not self:collide_floor() then self.grounded = false end
                if not self.grounded then self:collide_ceiling() end
                if not self:collide_walls() then self.walled = false end     
            end,
            apply_world_physics = function(self) -- wraps collisions and gravity
                self:fall()
                self:collide()
            end,
            update_pos = function(self) -- updates self.pos vector         
                if(not self.walled) self.pos.x+= self.spd.x 
                self.pos.y += self.spd.y
            end,
            update_frame = function(self) -- updates self.frame
                if(time%self.sprites[self.state].rate == 0) then 
                    self.frame = (self.frame % (#(self.sprites[self.state])) ) +1 
                end
                if(self.sprites[self.state][self.frame]==nil)then self.frame=1 end
            end,
            grounded = false, walled = false,
            maxspd = 1, maxyspd = 4, offset = 0, 
            state = STILL, clop=0.5,
            height=8,width=6,bx=2,by=0,
            spd = v(0,0), acc=v(0,0), finpos = v(0,0), pos=v(0,0),
            frame=1,sprites={{rate=0,1}}
        }, -- ok

        ['character']={ --2  character  
            -- require: blackline 
            function(self) -- draw()
                self.watering = self.controller&(1<<4) != 0
                dx = (self.direction and -1) or 1 
                oy = (self.watering and 0) or 1
                ox = (self.watering and 4*dx) or 2*dx
                
                --blackline(44,self.pos.x - (self.width/2) - 3 +  dx + ox,self.pos.y-self.height/2-3 + oy,1,1,self.direction,1)
                spr(44,self.pos.x - (self.width/2) - 3 +  dx + ox,self.pos.y-self.height/2-3 + oy,1,1,self.direction)
                self:draw_sprite()      

            end,

            function(self) -- update()
                self:do_action()
                self:move()
                self:apply_world_physics()
                self:update_pos()
                
                self:set_state()
                self:update_frame()
            end,

            init = function(self)
                self.sprites = {self.a_running,self.a_still,self.a_running,self.a_running,self.a_running,self.a_inair2,self.a_climbing,self.a_inair1,self.a_talking}
                self.phase = rnd(1)
                add(self.act_queue,self.control)
            end,
            set_state = function(self)
                if(self.spd.x<0) then 
                    self.state = RUNNING_R
                    if(self.controller==1) then
                        self.direction = RIGHT
                    end
                end
                if(self.spd.x>0) then 
                    self.state = RUNNING_L
                    if(self.controller==2) then
                        self.direction = LEFT
                    end
                end
                if(not self.grounded ) then 
                    if(self.climbing)then self.state = CLIMBING else
                        if(self.spd.y>0) then
                        self.state = IN_AIR_1
                        else self.state = IN_AIR_2 end
                    end
                end
                if(self.spd.x == 0 and self.grounded) then self.state = STILL end
                if(self.talking) self.state=TALKING 
            end,

            move = function(self)
                if(not self.climbing) then
                    for i=0,4 do 
                        if( (self.controller >> i) & 1 == 1) then self.moves[i+1](self) end 
                    end
                else
                    for i=2,4 do 
                        
                        if( (self.controller >> i) & 1 == 1) then self.moves_climbing[i+1](self) end 
                    end
                    if(self.controller & 12 == 0 ) then self.spd.y = 0 return end
                    if(self.controller & 3 == 0 ) then stop(self) end
                end
            end,

            apply_world_physics = function(self)
                if(not self.climbing) then
                    self:fall()
                    self:collide()

                    local monte_sur_une_echelle = (self:on_block(2) and (self.controller & 12 != 0))

                    if(monte_sur_une_echelle) then 
                        self.climbing = true 
                        self.pos.x = flr((self.pos.x+self.width/2)\8 )*8 +self.width/2 +1
                        self.spd.x=0
                        self.grounded = false
                    end
                else
                    self:climb()
                end
            end,

            climb=function(self)
                local tile1=mget((self.pos.x+2)/8,(self.pos.y)/8)
                local tile2=mget((self.pos.x+2)/8,(self.pos.y+self.spd.y+(9))/8)

                if(not fget(tile1,1)) then
                    self.pos.y = flr((self.pos.y-1)/8 )*8 + 8
                    if( (on_ground) and (self.controller & 3 != 0)) then self.climbing = false end
                    --return
                end
                if(not fget(tile2,1)) then
                    self.pos.y = flr((self.pos.y+4)/8 )*8 
                    --return
                end
                if(not (self.controller & 12 != 0) and fget(tile2,0) and (self.controller & 3 != 0)) then 
                    self.climbing = false 
                end

            end,

            aim_move = function(self,button) self.controller |= (1<<button) end,
            do_action = function(s) -- call the first function in the action stack, if it returns true then del
                if(#s.act_queue != 0) then   
                    local a = s.act_queue[#s.act_queue]
                    if(a(s)) then del(s.act_queue,a)end
                end
            end,

            control = function(s)
                if(time%10==0)then
                    
                    s.controller=0
                    stop(s)
                    local r=rnd(1)
                    if(r>0.8) then s:aim_move(flr(rnd(5)))end
                end
            end,

            moves = {go_right,go_left,go_up,go_down,
            function(s)
                addwater(s.pos.x - (s.width/2) +  dx*5 + ox+0.7,s.pos.y-s.height/2 +1,s.direction,s.spd)
            end
            },
            moves_climbing = {nil,nil,go_up,go_down,function(self)self.climbing=false end},
            act_queue = {},
            -- animations:
            -- premier element du tab = "vitesse" de l'animation, reste = les frames.
            a_running = {rate=a_MEDIUM,2,24,23,39,55,40,56},
            a_still = {rate=a_SLOW,9,25},
            a_inair1 = {rate=0,23},a_inair2 = {rate=0,41},
            a_climbing = {rate=a_MEDIUM,54,38,54,22},
            a_talking = {rate=a_MEDIUM,9,26},

            controller = 0,
            climbing = false,talking=false,watering=false,
            height=7,width=4,bx=3,by=1

        },

        ['player']={ --5 player (extends character)
            nil,nil,
            control = function(self)
                self.controller = 0
                for i=0,5 do
                    if(btn(i,self.gamepad_nb)) then self:aim_move(i) end
                end
                if(not btn(0,self.gamepad_nb) and not(btn(1,self.gamepad_nb))) then stop(self) end
            end,
            gamepad_nb=0
        },
        ['joe']={

        },
        ['flower']={
            function(self)end,function(self)end,
            init=function(self)
                self.color=rnd(15)
                mset(x\8,y\8,48)
            end,
            bloom=false,color=7,pos=v(0,0)
        }
    }

    function new_entity(class_id,args,skip_init)
        local entity
        local parent = inheritance[class_id]
        local its_class = entity_classes[class_id]

        if(parent != nil) then
            entity = new_entity(parent,args,true)
        else
            -- entite par defaut
            entity = { draw=nul, update=nul, init=nul, action=nul }
        end
        for k,val in pairs(its_class)do
            if(type(val) == "table") then -- if val is a table, copy it (if we don't do this, it will just put the reference)
                local copy = {}
                for o_k, o_v in pairs(val) do copy[o_k] = o_v end 
                entity[k] = copy
            else 
                entity[k] = val 
            end
        end
        for k,v in pairs(args or {}) do -- add properties from the arguments
            entity[k]=v
        end
        entity.draw,entity.update=its_class[1] or entity.draw,its_class[2] or entity.update
        if(not skip_init) then  entity:init() end
        return entity
    end
--

--####################################
--####################################
joe=new_entity('character',{
    pos=v(30,10),
    a_still={rate=a_MEDIUM,17},
    a_running={rate=a_SLOW,18,19},
    a_inair1={rate=a_MEDIUM,20},
    a_inair2={rate=a_MEDIUM,21}
    })
p=new_entity('player',{
    pos=v(50,10),
    a_still={rate=a_MEDIUM,1},
    a_running={rate=a_SLOW,2,3},
    a_inair1={rate=a_MEDIUM,4},
    a_inair2={rate=a_MEDIUM,5}
    })


add(entities,joe)
add(entities,p)




------

-- init update draw
--####################################

function _draw()
    cls(7)
    
    --rectfill(0,0,126,10,1)
    --rectfill(0,40,126,50,7)
    	
	line(0,8,128,8,12)	
	rectfill(0,11,128,14,12)   
    rectfill(0,16,128,100,12)

    map()
    for e in all(entities) do e:draw()end
    draw_water()
end

function _update()
    for e in all(entities) do e:update()end

    update_water()
    time=time%100 +1
end

__gfx__
00000000005555000055550000555500005555000055550000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555555555555555555555555555555555555500000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000068f80000668f0000668f0000668f0000668f0000000000000000000000000000000000000000000000000000000000000000000000000000000000
0007700000ffff0000ffff0000ffff0002ffff00f2ffff0000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000022222000022220000222200f02222000022220000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700f01111000002f100002f1100001111000011110000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000001001000011001000010100911000100011010000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000009009000090009000090900000000900900090000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000
000000000ffff00000ffff0000ffff0000ffff000ffff0000ffff040000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000
000000000f8f800000ff8f0000ff8f0000ff8f000f8f80400f8f80f0000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000
2f0000000f7f700000ff7f0000ff7f0000ff7f000f7f70f00f7f7540000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000
00000000057770400054770005457700f05777000577754005787040000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000
00000000517775f0005f770005f17700051771005177704051777040000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000
00000000f1111040001400100041010000100010f1111040f1111000000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000
00000000090090400094009000490900090000900900900009009000000000000000000000000000bbbbbbbb0000000000000000000000000000000000000000
00000000333333330aaa5aa04444444444444444333333333333330033333333003333333b444444444444444444444400000000000000000000000000000000
00000000bbbbbbbbaaaaaaaa4444444444444444bbbbbbbbbbbbbb30bbbbbbbb03bbbbbbb4444444444444444444444400000000000000000000000000000000
0000000044444444aa5aaa5a4444444454444444544444b444444bb3444444443b4444b444444444444444444444444400000000000000000000000000000000
00000000444445545aaaaaaa444444444444444444444444444444b3444444443b4444444444444454444444444444450000000000d000000000000000000000
0000000044444444aaaaaaaa444444444444444444444444444444b3444544443b444444444444440444444444444440000000000d0d00600000000000000000
f000000045555444aaaaaaaa44444444444444454444444544444bb3444444443b44444444444444054444444444445022fd00600d0d0d000000000000000000
0000000045555444aa5aaaaa44444444444444444444444444544bb3444444443b44444444444444005444444444450000dddd000ddddd000000000000000000
00000000444444440aaaaa50444444444444444444444444444444b3444444443bb44444444444440000544444450000000dd0000dddd0000000000000000000
00000000000000000000000000000000000b00000000000000000000000000000000000000077700007777700000000000000000000000000022220000000000
000000000000000000000000000000000000b030000000000000000000000000000000000003a3000003a3000000000000000000000000000200002000000000
000000000000700000077000000000000000b330000000000000000000000000000373000000b0000030b0300000000000000000000000002000000200000000
000aa000007aa000007aa700000000000000b3000000000000000000000000000000a0000000b0000000b0000000000020022002200220022000000200000000
000aa000000aa700007aa700000000000000b0000030000000000030000000000000b0000000b0000000b000000000006dd26dd26dd26dd22000000200000000
0000b0000007b0000007700000000000000b00000330000000000030000000000000b000000bb000000bb0000000000020022002200220022000000200000000
000b0000000b0000000b000000000000000b00000b0003000003003000000000000bb000000b0000000b0000000000006dd26dd26dd26dd22000000200000000
000b0000000b0000000b000030b00b03000b0000333b33b3bbbb333333000303000b0000000b0000000b0000b00b00b020022002200220022000000200000000
00000000000000000000000000000000000000006666666600000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000006cccc6c600000000000000000000000000000000000000000000000000000000000000000000000000000000
0300000000000000030000000300000030003000644444c600000000000000000000000000000000000000000000000000000000000000000000000000000000
0300000000330000030000000300000003030000640404c600000000000000000000000000000000000000000000000000000000000000000000000000000000
0333000003003000033300000333000000300000644444c600000000000000000000000000000000000000000000000000000000000000000000000000000000
03030000030030000303000003030000003000006111118600000000000000000000000000000000000000000000000000000000000000000000000000000000
033300000033000003330000033300000030000061111a7e00000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000666666c600000000000000000000000000000000000000000000000000000000000000000000000000000000
00330000003330000330330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00440000034443000440440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00440000040004000440440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00443300040004000440440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00400040040004000444400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00400040040004000004400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00400040040004000004400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00044400004440000004400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000700070007070707070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000003e3d3c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000003c3c003c28252525000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3c00000000000000282121212129242423000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2521212121212121292424242424242323000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2424242424242424242424242424242323000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2424242424242424242424242424242400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2424242424242424242424242424242400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
