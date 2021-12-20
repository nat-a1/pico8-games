pico-8 cartridge // http://www.pico-8.com
version 32
__lua__

-- our goal now will be to try to keep this to minimum 
STILL=1
-------------- game params
--------------------------------------
    GRAVITY = 0.3
    --seed = 18
    seed = rnd(120) srand(seed)
--------------------------------------

--------------- game
--------------------------------------
    game={
        cur_level=0,
        levels={},
        cur_checkpoint={}
    }
    story={}

--------------------------------------
---- useful, various
----------------------------------------
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
    time = 0 c = 0 -- useful counters?

    --- player constants
    RIGHT = true LEFT = false
    RUNNING_R = 1 RUNNING_L = 3
    STILL = 2 CLIMBING = 7 TALKING = 9
    MOVE_DOWN = 4 MOVE_UP = 5
    IN_AIR_1 = 6 IN_AIR_2 = 8
    a_MEDIUM = 2 a_VERY_SLOW = 20

    gr = {}

    function blackline(s,x,y,h,w,d,col)
        local _col=col or 0
        for i=1,15 do pal(i,col) end
        spr(s,x-1,y,h,w,d)
        spr(s,x+1,y,h,w,d)
        spr(s,x,y-1,h,w,d)
        spr(s,x,y+1,h,w,d)
        pal()
    end

--------------vecteurs
---------------------------------------
    vec={} vec.__index = vec
    --
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
----------------------------------------

-- external moving functions (--> move to character class)
    function go_left(p) 
        if(p.spd.x < p.maxspd) then p.spd.x +=0.2 end
        p.offset = p.clop*cos(4*t()+ p.phase)
    end
    function go_right(p)
        if(p.spd.x >-p.maxspd) then p.spd.x -=0.2 end
        p.offset = p.clop*cos(4*t()+ p.phase)
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


entities = {}
inheritance = {
    ['character']='object',
    ['player']='character',
    ['something']='object'
}


local entity_classes = {

    ['object']={ --3 objet physique
        -- required: vectors, GRAVITY, states(STILL), time,c?
        function(self)
            self:draw_sprite()
        end,nil,
        draw_sprite = function(self)

            local anim_list = self.sprites[self.state]
            local ox,oy =  (self.width/2 + self.bx ),   (  self.height/2 + self.by)
            spr(anim_list[self.frame+1],self.pos.x -ox,self.pos.y-oy + self.offset,1,1,self.direction)

        end,
        
        -------- additionnal, mus2
        collide_object_top=function(self) 

            if self.spd.y<0 then
                return false
            end
            for o in all(platforms) do

                local bounds = {
                    x0=o.pos.x-o.width/2,y0=o.pos.y-o.height/2,
                    x1=o.pos.x+o.width/2,y1=o.pos.y+o.height/2
                }

                if(self.pos.x-self.width/3<bounds.x1 and self.pos.x+self.width/3>bounds.x0 and
                    (self.pos.y+self.height/2-1 )<bounds.y1 and self.pos.y+self.height/2+2>bounds.y0) then
                    
                    -- change this
                    self.pos.y = bounds.y0 - self.height/2 
                    self.pos.x += o.spd.x
                    self.grounded = true
                    
                    self.spd.y=0
                    
                    return true

                end
            end
            return false
        end,
        collide_spikes=function(self) 

            if self.spd.y<0 then
                return false
            end
            for o in all(spikes) do
                local bounds = {
                    x0=o.pos.x*8,y0=o.pos.y*8 +4,
                    x1=(o.pos.x+1)*8,y1=(o.pos.y+1)*8
                }

                if(self.pos.x-self.width/3<bounds.x1 and self.pos.x+self.width/3>bounds.x0 and
                    (self.pos.y+self.height/2-1 )<bounds.y1 and self.pos.y+self.height/2+2>bounds.y0) and
                    o.state == 1 then
                    return true

                end
            end
            return false
        end,
        
        -------- 
        collide_floor = function(self)
            --only check for ground when falling.
            if self.spd.y<0 then
                return false
            end

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
            --only check for ground when falling.
            if self.spd.y>0 then
                return false
            end
            --local w = self.width + self.bx
            --local h = self.height+ self.by
            --local tile1=mget((self.pos.x+self.bx +2)/8,(self.pos.y+self.by+self.spd.y)/8)
            --local tile2=mget((self.pos.x+w -2)/8,(self.pos.y+self.by+self.spd.y)/8)
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
        on_that_block = function(self,flag)
            local t1=mget((self.pos.x-self.width/2)/8,(self.pos.y-self.height/2)/8)
            local t2=mget((self.pos.x+self.width/2)/8,(self.pos.y-self.height/2)/8)
            local t3=mget((self.pos.x-self.width/2)/8,(self.pos.y+self.height/2)/8)
            local t4=mget((self.pos.x+self.width/2)/8,(self.pos.y+self.height/2)/8)
            if(band(fget(t1), band(fget(t2),band(fget(t3),band(fget(t4),flag))))!=0) then return true
            else return false end
        end,
        fall = function(self)
            if(self.spd.y<self.maxyspd) then
                self.spd.y += GRAVITY 
            end
        end,
        collide = function(self)
            if (not self:collide_floor() and not self:collide_object_top()) then self.grounded = false end
            if (not self.grounded) then self:collide_ceiling() end
            if(not self:collide_walls()) then self.walled = false end    
            self:collide_spikes()   
        end,
        apply_world_physics = function(self)
            self:fall()
            self:collide()
        end,

        update_pos = function(self)
            
            if(not self.walled) self.pos.x+= self.spd.x 
            self.pos.y+=self.spd.y
            if(self.referentiel != nil) then
                self.pos = self.referentiel.pos+v(0,0)
                self.direction = self.referentiel.direction
            end
        end,
        
        update_frame = function(self)
            if(time%self.sprites[self.state][1]==0 and c) then 
                self.frame = (self.frame% (#(self.sprites[self.state])-1) ) +1 
            end
            if(self.sprites[self.state][self.frame+1] == nil) then self.frame = 1 end
        end,
        init=function(s) end,
        grounded = false, walled = false,
        maxspd = 1.7, maxyspd = 4, offset = 0, phasse = 0,
        state = STILL, curr_anim = {0}, clop=0.5,
        height=8,width=6,bx=2,by=0
    },

    ['character']={ --2 brainless character  
        -- require: blackline 
        function(self)
            self:_draw()
        end,

        function(self)
            self:do_action()
            self:move()
            self:apply_world_physics()
            self:update_pos()
            
            self:set_state()
            self:update_frame()
        end,
        _draw=function(s)end,
        main_draw=function(self)
            local anim_list = self.sprites[self.state]
            local ox,oy = - self.width/2 - self.bx ,  - self.height/2 - self.by
            blackline(anim_list[self.frame+1],self.pos.x + ox,self.pos.y+ oy + self.offset,1,1,self.direction)
            --pal(2,self.color)
            self:draw_sprite()
            pal()
        end,

        init = function(self)
            self.sprites = {self.a_running,self.a_still,self.a_running,self.a_running,self.a_running,self.a_inair2,self.a_climbing,self.a_inair1,self.a_talking}
            self.color = 1+rnd(8)
            self.phase = rnd(1)
            self.tempTar = v(0,0)
            self._draw=self.main_draw
            add(self.act_queue,self.control)self.pos=v(4*8,0)
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
            local xmv = false
            if(not self.climbing) then
                for i=0,2 do 
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

                local monte_sur_une_echelle = (self:on_that_block(2) and (self.controller & 12 != 0))
                if(monte_sur_une_echelle) then 
                    self.climbing = true 
                    self.pos.x = flr((self.pos.x+self.width/2)\8 )*8 +self.width/2 +1
                    self.spd.x=0
                    self.grounded = false
                end
            else
                self:how_to_climb()
            end
        end,

        how_to_climb=function(self)
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
        do_action = function(s)
            if(#s.act_queue != 0) then   
                local a = s.act_queue[#s.act_queue]
                --while(true)do print("babaorum") end
                if(a(s)) then del(s.act_queue,a)end
            end
        end,

        popa=function(s)
            del(s.act_queue,s.act_queue[#s.act_queue])
        end,

        control = function(s)end,
        moves = {go_right,go_left,go_up,go_down},
        moves_climbing = {nil,nil,go_up,go_down,function(self)self.climbing=false end},
        act_queue = {},
        pos = v(4*8,2*8), spd = v(0,0), color = 2,
        
        
        inventaire = {},
        -- animations:
        -- premier element du tab = "vitesse" de l'animation
        -- reste = les frames.
        a_running = {2,24,23,39,55,40,56},
        a_still = {a_MEDIUM,9,9,9,9,9,9,9,9,9,9,9,9,9,25},
        a_inair1 = {a_MEDIUM,23,23},a_inair2 = {a_MEDIUM,41,41},
        a_climbing = {a_MEDIUM,54,38,54,22},
        a_talking = {a_MEDIUM,9,26},

        controller = 0,
        climbing = false,
        height=7,width=4,bx=3,by=1,talking=false

    },

    ['player']={ --5 player (extends character(2))
        nil,nil,
        control = function(self)
            self.controller = 0
            for i=0,5 do
                if(btn(i,self.gamepad_nb)) then self:aim_move(i) end
            end
            if(not btn(0,self.gamepad_nb) and not(btn(1,self.gamepad_nb))) then stop(self) end
        end,
        color = 2,gamepad_nb=0
    },
    
    ['camera']={ --7 camera 
        function(self)
            clip(self.offset.x,self.offset.y,self.screen_w,self.screen_h)
            camera(self.pos.x-self.offset.x,self.pos.y-self.offset.y)
                       
           -- clip(self.offset.x,self.offset.y,self.screen_w,self.screen_h)
        end,
        function(self)
            local tarspd = @v(self.target.spd.x,self.target.spd.y)
            if(#tarspd != 0) then 
                self.sees += tarspd self.sees = self.sees | 20 
                --self.sees = tarspd * 20
            end
            local tarpos = v(self.target.pos.x,self.target.pos.y)

            if((game.cur_level.y1 - game.cur_level.y0)*8 <self.screen_h)then
                tarpos.y =( (game.cur_level.y1 + game.cur_level.y0)*8)/2 

            else
                if(tarpos.y - self.screen_h*0.4   < game.cur_level.y0*8)then
                    tarpos.y = game.cur_level.y0*8 + self.screen_h*0.4 - self.screen_h/6

                end
                if(tarpos.y + self.screen_h*0.4  > game.cur_level.y1*8)then
                    tarpos.y = game.cur_level.y1*8 - self.screen_h*0.4 - self.screen_h/6
                end
            end
            if((game.cur_level.x1 - game.cur_level.x0)*8 <self.screen_w)then
                tarpos.x =( (game.cur_level.x1 + game.cur_level.x0)*8)/2 
            else
                if(tarpos.x - self.screen_w*0.4  < game.cur_level.x0*8)then
                    tarpos.x = game.cur_level.x0*8 + self.screen_w*0.4

                end
                if(tarpos.x + self.screen_w*0.4  > game.cur_level.x1*8)then
                    tarpos.x = game.cur_level.x1*8 - self.screen_w*0.4
                end
            end

            local dir = ( tarpos - v(self.screen_w/2,self.screen_h/2 ) ) - self.pos

            self.spd = dir / 5
            self.spd = self.spd | 4

            self.pos += self.spd 


            
            --if(self.pos.x<0 ) self.pos.x=0
            --if(self.pos.x + 128>8*100 ) self.pos.x=8*100 -128
           -- if(self.pos.y<0 ) self.pos.y=0
            self.finpos = v(flr(self.pos.x),flr(self.pos.y))
        end,
        set_clip_region=function(self,o_x,o_y,w,h)
            self.offset= v(o_x,o_y)
            self.screen_w,self.screen_h = w,h
        end,
        pos = v(0,0), spd = v(0,0), target = v(0,0), offset = v(64,60),screen_w=128,screen_h=128, sees = v(0,0),
        set_target = function(self,the_entity)
            self.target = the_entity
        end,
        instant_change = function(s)
            s.pos = s.target.pos  - v(s.screen_w/2,s.screen_h/2 )
            s.sees = v(0,0)
        end,
        shake=function(s,i)
            _i = i or 4
            s.offset = v(_i/2-rnd(_i),_i/2-rnd(_i))
        end


    },

    ['something']={
        nil,
        function(self)
        
        self:apply_world_physics()
        self:update_pos()end,
        sprites={{0,1},{0,1}}
    }

}

function new_entity(class_id,_pos,skip_init)
    local entity
    local parent = inheritance[class_id]
    local its_class = entity_classes[class_id]
    if(parent != nil) then
        entity = new_entity(parent,_pos,true)
    else
        -- entite par defaut
        entity = {

            draw=nul, update=nul, init=nul, action=nul,

            pos = _pos or v(0,0), spd = v(0,0), acc=v(0,0), finpos = v(0,0), ofs1 = v(0,0),ofs2 = v(0,0),
            frame = 1,spriteset=1, sprites = {{1,2}}, direc = RIGHT, main_color=10,color=10, framerate=1,
            referentiel = nil,
            
            draw2= function(self) self:draw() end,
        }
    end
    for k,val in pairs(its_class)do
        if(type(val) == "table") then
            local copy = {}
            for o_k, o_v in pairs(val) do copy[o_k] = o_v end
            entity[k] = copy
        else
            entity[k] = val
        end
    end
    entity.draw,entity.update=its_class[1] or entity.draw,its_class[2] or entity.update
    if(not skip_init) then 
        entity:init() 
    end
    return entity
end

for i=1,3 do
    rand_x = flr(rnd(10))
    random_object = new_entity('something',v(16 + 8 * rand_x,10))
    add(entities,random_object)
end

p=new_entity('player',v(30,10))
p.a_still={a_MEDIUM,8}
p.a_running={a_MEDIUM,8,9,10,11}
p.a_inair1={a_MEDIUM,9}
p.a_inair2={a_MEDIUM,10}
p:init()



add(entities,p)

function _draw()
    cls(1)
    map()
    for e in all(entities) do e:draw()end
end

function _update()
    for e in all(entities) do e:update()end
end

__gfx__
00000000dddddddd2222222200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000d000000d2222222200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700d090090d222222220000000000000000000000000000000000000000008e8000008e8000008e8000008e800000000000000000000000000000000000
00077000d000000d22222222000000000000000000000000000000000000000000eee00000eee00000eee00000eee00000000000000000000000000000000000
00077000d009000d22222222000000000000000000000000000000000000000000ddd00000ddd00000ddd00000ddd00000000000000000000000000000000000
00700700d000009d22222222000000000000000000000000000000000000000000ddd00000ddd00000ddd00000ddd00000000000000000000000000000000000
00000000d900000d22222222000000000000000000000000000000000000000000d0d00009d0d0000090d00000d0d90000000000000000000000000000000000
00000000dddddddd2222222200000000000000000000000000000000000000000090900000009000000090000090000000000000000000000000000000000000
__gff__
0000070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
0000000000000000000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000002000202020202020000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000200000000000000020202020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000200000000000000000000020000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0202020202020202020202020202020000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
