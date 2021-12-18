pico-8 cartridge // http://www.pico-8.com
version 32
__lua__

-------------- game params
--------------------------------------
    GRAVITY = 0.3
    --seed = 18
    seed = rnd(120) srand(seed)
    dynamic_music=false
--------------------------------------

-------------- various params
--------------------------------------
    local ch2,ch1l,ch1h,ch2l,ch1h2=0,0,0,0,0
    local ptn=0
    local sfx_addr = 0x3200
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

--------------timer
----------------------------------------
    function new_timer()
        local c = {
            t=10,
            set=function(s,t) s.t=t end,
            elapsed=function(s) if(s.t <= 0)return true else s.t -=1 return false end
        }
        return c
    end
----------------------------------------

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
    poke(0x5f2d, 0x1)

    function blackline(s,x,y,h,w,d,col)
        local _col=col or 0
        for i=1,15 do pal(i,col) end
        spr(s,x-1,y,h,w,d)
        spr(s,x+1,y,h,w,d)
        spr(s,x,y-1,h,w,d)
        spr(s,x,y+1,h,w,d)
        pal()
    end
----------------------------------------

----------------- particles: dust, dependencies:vectors
----------------------------------------
    dust = {
        draw=function(s)
            for d in all(s) do circfill(d.pos.x,d.pos.y,d.s,6) end
        end,
        update=function(s)
            for d in all(s) do

                d.pos += d.spd
                d.spd *= 0.9

                d.l -= 1
                d.s -= 0.1

                if(d.l<0) then del(s, d) end
            end
        end,
        make=function(s,x,y)
            d = {
                pos= v( x-5+rnd(10), y-1 ),
                spd= v( 0.5-rnd(1) , - rnd(0.5)),

                s = 1+rnd(1),
                l = 10+flr(rnd(5))
            }
            add(s,d)
        end
    }

    --- creates a puff, = producing a random amount of dust
    function puff(xx,yy,intensity)
        local r = flr(rnd(6))
        for i=1,r do
            dust:make(xx+4,yy+7)
        end
    end
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

level1={}

entities = {}
inheritance = {
    ['character']='object',
    ['idk']='object',
    ['player']='character',
    ['wise pnj']='character',
    ['player 2']='player',
    ['spike']='dyna wall',
    ['dyna wall2']='dyna wall',
    ['computer']='switch'
}

local entity_classes = {

    ['object']={ --3 objet physique
        -- required: vectors,puff, GRAVITY, states(STILL), time,c?
        function(self)
            self:draw_sprite()
        end,nil,
        draw_sprite = function(self)
            pal(11,0)
            local anim_list = self.sprites[self.state]
            local ox,oy =  (self.width/2 + self.bx ),   (  self.height/2 + self.by)
            spr(anim_list[self.frame+1],self.pos.x -ox,self.pos.y-oy + self.offset,1,1,self.direction)
            pal()
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
                            
                    if(self.spd.y > 2) then puff(self.pos.x-self.width,self.pos.y) end
                    
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
                    
                   
                    if(self.spd.y > 2) then puff(self.pos.x-self.width,self.pos.y) end
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
                    
                   
                    if(self.spd.y < 1) then puff(self.pos.x-self.width,self.pos.y-self.height) end
                    self.spd.y = 0
                    return true
                end
            end
            return false
        end,
        collide_walls = function(self)

            --if(self.spd.x == 0) then return false end
            --local offset = self.bx
            --local w  = self.width
            --local h = self.by+self.height
            --if(self.spd.x>0) then offset = w+self.bx end
            --local tile1=mget((self.pos.x+offset  )/8,(self.pos.y+self.by+1)/8)
            --local tile2=mget((self.pos.x+offset )/8,(self.pos.y+h-1)/8)
           --     if(fget(tile1,0) or fget(tile2,0)) then
            --        self.walled = true
            --        self.x = ((flr((self.pos.x - offset ))/8) *8)+8+offset
            --        return true
            --    end

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
        init=function(s)s.pos=v(0,0)end,
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
        take=function(s,l,o) 
            local obj=del(l,o) obj.referentiel=s
            add(s.inventaire,obj) end,
        drop=function(s,l,o) 
            local obj=del(l,o) obj.referentiel=nil
            add(l,del(s.inventaire,obj)) 
        end,
        popa=function(s)
            del(s.act_queue,s.act_queue[#s.act_queue])
        end,

        control = function()end,
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
        die=function(self)
            self.dead=true

            local f=function(s)

                s.spd=v(0,0)
                GRAVITY=0

                s._draw=cowrap(s.die_draw)
                return true
            end
            add(self.act_queue,cowrap(f))
        end,
        collide = function(self)
            if (not self:collide_floor() and not self:collide_object_top()) then self.grounded = false end
            if (not self.grounded) then self:collide_ceiling() end
            if(not self:collide_walls()) then self.walled = false end    
            if(self:collide_spikes() and not self.dead) then self:die() end
        end,
        respawn=function(s)
            GRAVITY=0.3
            targ = v(game.cur_checkpoint.pos.x+8,game.cur_checkpoint.pos.y)
            s.pos=targ
        end,

        die_draw=function(s)
            
            local anim_list = s.sprites[s.state]
            local ox,oy = - s.width/2 - s.bx ,  - s.height/2 - s.by
            
            for p = -1.5, 3.75, 0.5 do
                s.controller=0
                srand(p)
                camera1:shake(7/(0.5+(1.5+p)))
                local i = 4 - flr(abs(p))
                local bg, fg =
                    ({0, 0, 5, 3})[i],
                    ({5, 3, 11, 10})[i]
                --cls(bg)
                circ(s.pos.x, s.pos.y, p * 4 + 12, fg)
                local angle = -0.3125 - p/24
                local dx, dy = 256*cos(angle),
                    256*sin(angle)
                --line(s.pos.x-dx, s.pos.y-dy, s.pos.x+dx, s.pos.y+dy, fg)
                --line(s.pos.x-dy, s.pos.y+dx, s.pos.x+dy, s.pos.y-dx, fg)
                local _c = 7
                --blackline(41,s.pos.x + ox,s.pos.y+ oy + s.offset,1,1,s.direction,fg)
                yield()
            end
            
            s:respawn()
            for p = 3.75, -3.75, -0.5 do
                
                local i = 4 - flr(abs(p))
                local bg, fg =
                    ({0, 0, 5, 3})[i],
                    ({5, 3, 11, 10})[i]
                --cls(bg)
                circ(s.pos.x, s.pos.y, p * 6 + 12, fg)
                local angle = -0.3125 - p/24
                local dx, dy = 256*cos(angle),
                    256*sin(angle)
                line(s.pos.x-dx, s.pos.y-dy, s.pos.x+dx, s.pos.y+dy, fg)
                line(s.pos.x-dy, s.pos.y+dx, s.pos.x+dy, s.pos.y-dx, fg)
                local _c = 7
                blackline(41,s.pos.x + ox,s.pos.y+ oy + s.offset,1,1,s.direction,fg)
                yield()
            end
            s._draw=s.main_draw
            s.dead=false
            --s:respawn()
        end,
        color = 2,gamepad_nb=0,dead=false
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
    
    ['player 2']={ --8 extends player
        nil,nil,
        color = 3,gamepad_nb=1
    },

    ['dyna wall']={--9 dynamic wall
        function(it)
            mset(it.pos.x,it.pos.y,it.sprites[it.state][it.frame])
            spr(it.sprites[it.state][it.frame],it.pos.x\8,it.pos.y\8)
        end,
        function(self)
            self:update_frame()
            if(self.patterns[ptn]!=nil) self:twinkle()
            --self:set_sprite()
            
        end,
        twinkle=function(it)
            --if(ch1h%1==0 and (it.state != 0))then
            --        it.state=0     
            --end

            if(ch1h%2==0 and ch2%32==(it.beattab[it.idx]+it.offset)%32)then
                    it.idx=(it.idx%#it.beattab)+1
                    it.state= ((it.state)%2) +1
                    it.frame=1
            end
        end,
        set_sprite=function(s)
            if(s.state==1)then 
                s.sprite=1 
            else 
                s.sprite=16 
            end
        end,

        update_frame = function(self)
            local cur_set=self.sprites[self.state]
            
            local loop = (cur_set.loop or self.frame!=#cur_set) 
            if(time%cur_set.rate==0 and c and loop) then 

                self.frame = (self.frame% (#cur_set+1) ) +1 

            end
            if(cur_set[self.frame] == nil) then 
                self.frame = 1 
            end
        end,
        sprites={
            {rate=1,35,1,1,loop=false},
            {rate=1,1,35,16,loop=false}
        },frame=1,
        beattab={0},patterns = {[2]=1,[3]={1},[4]={1},[5]={1},[6]={1}},
        offset=0,state=1,idx=1,sprite=1
    },

    ['rotating']={--10 rotating things
        draw_2 =function (it,size_,c_)
            local coul=c_
            for i=0,it.t_nb,2 do
                local r = (1 /it.t_nb)*( i) + it.rot
                local s=  ((size_)*(6.28))/it.t_nb
                
                circfill(it.pos.x+(it.size+1)*cos(r),it.pos.y+(it.size+1)*sin(r),s/2 -1,coul)
                circfill(it.pos.x+(it.size)*cos(r),it.pos.y+(it.size)*sin(r),(s/2 -1),coul)
                circfill(it.pos.x+(it.size-1)*cos(r),it.pos.y+(it.size-1)*sin(r),(s/2),coul)
            end

            
            circfill(it.pos.x ,it.pos.y,size_ -1,coul )
            --circfill(it.pos.x ,it.pos.y,it.size-10,0 )

            for i=1,4 do
                local r = (0.25)*( i) + it.rot
                circfill(it.pos.x + (size_-7)*cos(r) ,it.pos.y+(size_-7)*sin(r),1,0 )
            end
        end,
        function(it)
            it:draw_2(it.size,0)


            if(it.state==1) then 
                 it.rot += it.spd*it.dir
            end
        end,
        function(self)
            self:twinkle()
            --self:set_sprite()
        end,
        twinkle=function(it)
            --if(ch1h%1==0 and (it.state != 0))then
            --        it.state=0     
            --end

            if(it.beattabs[ptn]!=nil)then
                if((ch1h2%32)==(it.beattabs[ptn][it.idx]))then
                    it.state=(it.state%2)+1
                    it.idx=(it.idx%#it.beattabs[ptn]) +1
                end
            end
        end,
        random_init=function(it)
            local patterns = {1,2,3,4,5,6}

            it.size=4+(flr(rnd(20)))
            it.t_nb= 10 + 2*(flr(rnd(it.size\2)))
            it.dir= (flr(1+rnd(2)))*2 -3
            it.spd= 0.005+rnd(0.01)
            local mod= {2,4,8}
            local beattab = {}
            local j= mod[flr(rnd(#mod)+1)]
            for i=1,31 do
                if(i%j==0) beattab[#beattab+1]=i
            end
            beattab[#beattab+1]=0
            
            for p in all(patterns) do     
                it.beattabs[p]=beattab
            end
        end,

        offset=0,state=0,idx=1,sprite=1,pos=v(rnd(128),rnd(128)), rot=0,rad=20,dir=1,
        t_nb=10,size=20,spd=0.001,beattabs={}
    },

    ['spike']={ --11 spike extends dynawall
        sprites={
            {rate=1,50,49,49,loop=false},
            {rate=1,49,50,0,loop=false}
        }, beattab={0,8,16,24},patterns={[11]={1}},
    },

    ['moving platform']={
        function(self)
            self:draw_sprite()
        end,
        function(self)
            self:twinkle()
            

            self.pos += self.spd
            if(self.state==4) then
                self.spd = v(0,1)*1
                self.offset=cos(t()*10)*0.5
                
            end
            if(self.state==2) then
                self.spd = v(0,-1)*1
                self.offset=cos(t()*10)*0.5
            end 
            
        end,
        draw_sprite = function(self)
            pal(11,0)
            local anim_list = self.sprites[self.state]
            local ox,oy =  (self.width/2 + self.bx ),   (  self.height/2 + self.by)
            pal(7,self.color[self.state])
            spr(anim_list[self.frame+1],self.pos.x -ox+self.offset,self.pos.y-oy,1,1,0)
            pal()
        end,
        twinkle=function(it)
            --if(ch1h%1==0 and (it.state != 0))then
            --        it.state=0     
            --end

            if((ch1h%32)==(it.beattab[it.idx]))then
                    it.idx=(it.idx%#it.beattab)+1
                    it.state= ((it.state)%4) +1
                    --it.color=0*
                    it.spd = v(0,-1)*0
                    
                    if(it.state%2==1)then
                        puff(it.pos.x-it.width+2,it.pos.y-it.height-2,0.01)
                    end
            end
        end,
        height=4,width=8,bx=0,by=0,offset=0,
        sprites={{0,3},{0,3},{0,3},{0,3}},state=1,pos=v(0,0),spd=v(0,0),frame=1,color={0,11,0,8},idx=1,
        beattab={16,24}--28,59
    },

    ['beat thing']={
        function(self)
            local pat=░
            fillp(pat+.1)
            circfill(self.pos.x,self.pos.y,self.size+0.6*self.e,2)
            fillp(0)
            circfill(self.pos.x,self.pos.y,self.size/3+1.1*(self.e),2)
            

        end,
        function(self)
            if(self.patterns[ptn]!=nil) self:twinkle()
            if(self.e>0) then
                self.e=self.e*0.8
            end
        end,
        twinkle=function(self)
            
            --[[
            if(ch1h%2==0 and ch2%32==(self.beattab[it.idx])%32 /4)then
                    self.idx=(self.idx%#self.beattab)+1
                    self.state= ((it.state)%2) +1
                    self.frame=1
            end
            ]]--

            if((ch1h2)==(self.beattab[self.idx] / 2))then
                self.idx=(self.idx%#self.beattab)+1
                self.e+=6--(ch1h%8)

                local dist=(player.pos-self.pos)
                if(#dist<10) then
                    player.spd += (dist*(5/(max(#dist,1))) | 5)
                end
            end
            
        end,
        beattab={0,14,16,24,32,46,48,56},patterns={[11]={0}},
        e=0,idx=1, col=2,size=10
    },

    ['switch']={
        function(s)

            spr(s.sprites[s.state],s.pos.x,s.pos.y)
            if(s.show_sign) then
                print('🅾️',s.pos.x,s.pos.y-10,7)
                --circfill(s.pos.x,s.pos.y-10,2,2)
            end
        end,
        function(s)
            s:interact()
            s.frame=(s.frame%2)+1
        end,
        interact=function(s)
            local dist=(s.pos+v(4,4))-player.pos
            s.show_sign=false
            if(#dist<8 and #dist>0 and dialogues.done)then
                s.show_sign=true
                if(btnp(4)) then 
                    --game.cur_level=1 
                    s.on=true
                    s.state=2
                end
            end

        end,
        show_sign=false,on=false,
        sprites={32,48},state=1,frame=1
    },
    ['computer']={
        function(s)
            local anim_list = s.sprites[s.state]
            spr(anim_list[s.frame],s.pos.x,s.pos.y,2,2)
            if(s.show_sign) then
                print('🅾️',s.pos.x,s.pos.y-10,7)
                --circfill(s.pos.x,s.pos.y-10,2,2)
            end
        end,
        sprites={{96,98},{96,98}},state=1,frame=1
    },
    ['checkpoint']={
        function(s)
            pal(11,s.color)
            spr(116,s.pos.x,s.pos.y,2,1)
            pal()
        end,
        function(s)
            if(#(player.pos - s.pos)< 8) then s:turn_on() end
        end,
        turn_on = function(s)
            game.cur_checkpoint:turn_off()
            s.color=11
            game.cur_checkpoint=s
        end,
        turn_off = function(s) s.color=8 end,
        color=8
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

            pos = _pos, spd = v(0,0), acc=v(0,0), finpos = v(0,0), ofs1 = v(0,0),ofs2 = v(0,0),
            frame = 1,spriteset=1, sprites = {{1,2}}, direc = RIGHT, main_color=10,color=10, framerate=1,
            referentiel = nil,
            
            draw2= function(self)
                self:draw()
            end,
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

----------------------dialogue class
----------------------------------------
    dialogues = {
        montexte = {},
        bounds={x1=5,y1=90,x2=123,y2=128},
        var = 1, row=1, linlen = 0, counter = 0, effet = 0,
        wait = false,  done = true, 

        to_table=function(s,text)
            local t = {}
            for i=0,#text do add(t,sub(text,i,i))  end
            return t
        end,
        updtexte=function(s)
            s.counter = (s.counter+1) %30
            if(not s.wait) then
                if(s.counter%2==0) then
                    if (s.var<#s.montexte) then 
                        s.var+=1
                    else 
                        s.done = true 
                        s.draw = nul
                    end
                end
            else
                if(btn(0)) then 
                    s.wait = not s.wait 
                end
            end
        end,

        dialogue = function(s,text,suite,talker)
            s.var =0
            s.montexte = s:to_table(text)
            s.done = false
            s.draw = s.printexte

        end,

        printexte=function(s)
            local x,y = camera1.finpos.x+s.bounds.x1,camera1.finpos.y+s.bounds.y1
            rectfill(x,y,camera1.finpos.x+s.bounds.x2,camera1.finpos.y+s.bounds.y2,1)

            s.row=1 s.linlen=0 s.effet = 1
            for i=1,s.var do
                local ox, oy = 0,0
                if(s.montexte[i]=='|') then s.row+=1 s.linlen=0
                elseif (s.montexte[i]=='@') then s.effet= 1
                elseif (s.montexte[i]=='*') then s.effet= 2
                elseif (s.montexte[i]=='0') then
                    local new={}
                    for c=1,(i-1) do
                        deli(s.montexte,1) s.var=1
                    end
                    --s.montexte = new
                elseif (s.montexte[i]=='_') then s.effet= 0
                elseif (s.montexte[i]=='%') then 
                    s.wait = true s.montexte[i]="" 
                else
                    if(s.effet==1) oy = 2*sin(t()+i/4)
                    if(s.effet==2) ox = 0.125-rnd(0.25) oy = 0.25-rnd(0.5)
                    print(s.montexte[i],x+s.linlen*5 + ox ,8*s.row + y + oy +1,2)
                    print(s.montexte[i],x+s.linlen*5 + ox ,8*s.row + y + oy,7)

                    if(s.wait) print("🅾️",camera1.finpos.x+s.bounds.x2-10,camera1.finpos.y+s.bounds.y2-10)
                    s.linlen  +=1
                    
                end
            end
        end,

        draw=nul
    }
----------------------------------------

----------------------sound
----------------------------------------

    --{
        --[1]{1:'roue'} min dist from all dists of wheels.
        --      2: 'beat things' same, bro.
    --}


    local music_addr = 0x3100

    -- cette fonction ne marche pas totalement, evidemment.
    -- (si je veux retourner au niveau 1, il faut refaire la musique 1, qui est avant musique2)
    function update_music_loop(level) -- disables the end_loop, for the 1 frame.
        local b=level.music[1]
        local e=level.music[2]

        -- a) clear everything!!!
        for i=0,10 do
            local p = music_addr + 4*i
            poke(p,@(p)     & 0b01111111)
            poke(p+1,@(p+1)     & 0b01111111)
            if(i<=b) poke(p,@(p)     | 0b10000000)
            if(i>=e) poke(p+1,@(p+1) | 0b10000000)
        end
         
        -- b) set new begin and end
        local byte_begin = music_addr + b*4 
        local byte_end = music_addr + e*4 + 1
        poke(byte_begin,@(byte_begin) | 0b10000000)
        poke(byte_end,@(byte_end) | 0b10000000)
    end
----------------------------------------

----------------------cute spring stars
----------------------------------------
    stars={}

    function make_stars(level,density,shape) --shape is array-like
        for i=0,density do
            s={
                pos=v(0,0),acc=v(0,0),orig=v(0,0),l=level,
                speed=v(0,0),col=5, initcol=flr(rnd(2)),shp="",
                beattab={0,4,5,8,12,14,16,20,24,28,32},idx=1,
                init=function(it,x,y,xx,yy)
                    it.pos=v(x+rnd(xx-x),y+rnd(yy-y))    
                    it.orig=v(it.pos.x,it.pos.y)
                    it.shp=shape[flr(rnd(#shape)+1)]
                end,
                update=function(it,m)

                    it.acc=v(0,0)
                    local dist=(it.orig-it.pos)
                    local distmouse=(m.pos-it.pos)
                    local spring = (dist * 0.2) - (it.speed *0.1) | 1
                    it.acc +=  spring

                    local dm = #distmouse
                    --local close = abs(m.pos.x\8 - it.pos.x\8) <4 and abs(m.pos.y\8-it.pos.y\8 )<4
                    if((dm)<18 and it.l:isInside()and dm>0)then
                        --it.acc -= ((v(distmouse.x/dm,distmouse.y/dm)) *10) * 
    
                        it.acc -= (distmouse/20) * (#v(m.spd.x,m.spd.y)/3)
                        --it.speed-= distmouse*0.1
                    end

                    it.speed= (it.speed+ it.acc) |2
                    it.pos += it.speed 

                    it:twinkle()
                    
                end,
                draw=function(it)
                    pal(it.col,1)
                    print(it.shp,it.pos.x-1,it.pos.y,it.col)
                    print(it.shp,it.pos.x+1,it.pos.y,it.col)
                    print(it.shp,it.pos.x,it.pos.y-1,it.col)
                    print(it.shp,it.pos.x,it.pos.y+1,it.col)
                    pal()
                    print(it.shp,it.pos.x,it.pos.y,it.col)
                end,
                twinkle=function(it)
                    beattab={0,8,16,24}
                    if(ch1h%0.5==0 and (it.col != 5 or it.col !=2))then
                        it.col=5
                        if(#it.speed>0.1)then 
                            it.col=2
                        else 
                        end
                    end

                    if(ch1h%beattab[it.idx]==0)then
                        it.idx=(it.idx%#beattab)+1
                        local coltab={7}

                        if(it.col == 2)then
                        it.col=coltab[((it.idx+it.initcol)%2)+1]
                        end
                    end

                end
            }
            s:init((level.x0+1)*8,(level.y0+1)*8,(level.x1-1)*8,(level.y1-1)*8)
            if(stars[level]==nil) then stars[level]={} end
            add(stars[level],s)
            
        end
    end

    function draw_stars(m)
        for s in all(stars[game.cur_level]) do
            s:draw(m)
        end
    end
    function update_stars(m)
        for s in all(stars[game.cur_level]) do
            s:update(m)
        end
    end
----------------------------------------

----------------------function to easily create cameras
----------------------------------------
    cameras = {}
    function make_camera()
        local cam = new_entity('camera') 

        if(#cameras==0) then
            cam:set_clip_region(0,0,128,128)
        else
            cameras[1]:set_clip_region(0,0,128,64)
            cam:set_clip_region(0,64,128,64)    
        end

        add(cameras,cam)

        return cam
    end
----------------------------------------

-- ajouter une fonction qui retourne le niveau en fonction de paramれそtres x et y
-- (pour pouvoir spawner des objets plus facilement)
levels={
    current=0,
    init=function(s)
        current=1
    end,
    make=function(s,x0,y0,x1,y1,n,links)
        l={
            x0=x0,y0=y0,x1=x1,y1=y1,n=n,
            music={0},
            link=links,entities={},
            isInside=function(self)
                return (player.pos.x\8 >= self.x0  and player.pos.y\8  >=self.y0) and
                        (player.pos.x\8 < self.x1  and player.pos.y\8  <self.y1)
            end
        }
        add(s,l)
        return l
    end
}


local level1=levels:make(0,57,11,63,1,{2})
level1.music={0,0}
local level2=levels:make(11,57,54,62,2,{1,3,4})
level2.music={3,6}
local level3=levels:make(54,56,62,63,3,{2})
level3.music={2,2}
local level4=levels:make(00,47,25,57,4,{2,5})
level4.music={8,8}
local level5=levels:make(25,47,44,52,5,{4})
level5.music={11,11}
local level6=levels:make(24,52,55,57,6,{5,7})
level6.music={11,11}
local level7=levels:make(44,43,54,52,7,{6})
level7.music={11,11}

game.cur_level=level1

function draw_bg()

    local function draw_bg2(l)
        srand(1)
        pal(15,0)
        for i=l.x0+0.5,l.x1-1 do
            for j=l.y0,l.y1+1 do          
                spr(4+flr(rnd(5)),i*8,j*8,1,1)
            end
        end
        pal()
    end

    

    rectfill(game.cur_level.x0*8,game.cur_level.y0*8,game.cur_level.x1*8,game.cur_level.y1*8,1)
    draw_bg2(game.cur_level)
    for l in all(levels) do
        if(l:isInside())then
            for i in all(l.link) do
                local lk = levels[i]
                fillp(░+0.1)
                rectfill(lk.x0*8,lk.y0*8,(lk.x1+1)*8,(lk.y1+1)*8,1)
                fillp()
                rectfill((lk.x0+1)*8,(lk.y0+1)*8,lk.x1*8,lk.y1*8,0)
            end

            if(game.cur_level != l) then 
                game.cur_level=l 
                if(story.step>1) update_music_loop(l)
            end
        end
    end
end

--█▒🐱⬇️░✽●♥☉웃⌂⬅️😐♪🅾️◆…➡️★⧗⬆️ˇ∧❎▤▥

function init_player1()
    player = new_entity('player')
    player.pos = v(3*8,61*8)

    camera1 = make_camera()
    camera1:set_target(player)
    camera1:instant_change()
end

-- easy spawning
spikes={}

function spawn_objects()
    for i=0,128 do
        for j=0,128 do

            local tile=mget(i,j)
            -- dyna walls
            for k=0,3 do
                if(tile==28+k) then
                    w = new_entity('dyna wall')
                    w.pos = v(i,j)
                    w.offset=(k*4)%32
                    add(entities,w)
                    mset(i,j,0)
                end
                if(tile==12+k) then
                    w = new_entity('dyna wall')
                    w.pos = v(i,j)
                    w.offset=(k*4)%32
                    w.state=2
                    add(entities,w)
                    mset(i,j,0)
                end

                if(tile==44+k) then
                    w = new_entity('dyna wall')
                    w.pos = v(i,j)
                    w.offset=(k*4)%32
                    w.state=2
                    w.beattab={0,16}
                    w.patterns={[8]={1}}
                    add(entities,w)
                    mset(i,j,0)

                end
                if(tile==60+k) then
                    w = new_entity('dyna wall')
                    w.pos = v(i,j)
                    w.offset=((k*4) + 16) % 32
                    w.state=2
                    w.patterns={[8]={1}}
                    w.beattab={0,16}
                    add(entities,w)
                    mset(i,j,0)
                end
                if(tile==11) then
                    w = new_entity('dyna wall')
                    w.pos = v(i,j)
                    --w.offset=((k*4) + 16) % 32
                    w.state=2
                    w.patterns={[11]={1}}
                    w.beattab={0}
                    add(entities,w)
                    mset(i,j,0)
                end
                
            end

            -- spikes
            for k=0,1 do
                if(tile==49+k) then
                    w = new_entity('spike')
                    w.pos = v(i,j)
                    w.state= k+1
                    add(entities,w)
                    add(spikes,w)
                    mset(i,j,0)
                end
            end
            --char
            if(tile==9) then player.pos=v(i*8,j*8) mset(i,j,0)end
            
        end
    end
end




function spawn_gears()
    for i=0,10 do
        rot=new_entity('rotating')
        if(rnd(1)<0.5)then rot.pos=v(rnd(8*62),57*8 + 5-rnd(10))
        else rot.pos=v(rnd(8*54),63*8 + 5-rnd(10)) end
        rot:random_init()
        add(entities,rot)
    end
end

-- room 3
switch=new_entity('switch')
switch.pos=v(8*60,62*8-2)
add(level3.entities,switch)

-- room 4
switch2=new_entity('switch')
switch2.pos=v(8*22,50*8-2)
add(level4.entities,switch2)

-- room 5
b=new_entity('beat thing',v(29*8 ,48.5*8 ))b.size=11
add(level5.entities,b)

b=new_entity('beat thing',v(35*8 ,49.5*8 ))
b.beattab={0,16,32,48} b.size=6
add(level5.entities,b)

b=new_entity('beat thing',v(51*8 ,56*8 ))
b.beattab={0,16,32,48} b.size=8
add(level6.entities,b)
--
cmptr=new_entity('computer',v(8*8,61*8))
add(level1.entities,cmptr)

n=new_entity('checkpoint',v(1*8,62*8))
add(level1.entities,n)
game.cur_checkpoint=n
add(level5.entities,new_entity('checkpoint',v(27*8,51*8)))
add(level6.entities,new_entity('checkpoint',v(45*8,55*8)))

------------
story={
    step=1, timer= {},
    init=function(s)
        s.timer=new_timer()
        step=1
    end,
    update=function(s)
        s.cur_action=story[s.step]
        s:cur_action()
    end,
    cur_action=function(s)end,
    [1]=function(s)
        if(switch.on) then
            s.step+=1
            dialogues:dialogue("....?%")
            level3.music={1,1}
            update_music_loop(level3)
            music(1)
        end
    end,
    [2]=function(s)
        camera1:shake()
        if(dialogues.done)then
            s.step+=1
            level3.music={2,2}
            update_music_loop(level3)
        end
    end,
    [3]=function(s)
        if(switch2.on) then
            s.step+=1
            dialogues:dialogue("....????!!!!!%")
            level4.music={9,9}
            update_music_loop(level4)
            music(9)
        end
    end,
    [4]=function(s)
        camera1:shake()
        if(dialogues.done)then
            puff(24*8,49*8,100)
            puff(25*8,49*8,100)
            puff(25*8,50*8,100)
            puff(24*8,50*8,100)
            mset(24,49,0)mset(25,49,0)mset(24,50,0)mset(25,50,0)

            s.step+=1
            level4.music={10,10}
            music(10)
            update_music_loop(level4)
        end
    end,
    [5]=function(s)
        if(level5:isInside())then
            mset(24,49,1)mset(24,50,1)
            s.step+=1
        end
    end,
    [6]=nul
}
------------
---- main drawing functions
----------------------------------------
    ptn0=0
    function drawscreen() -- that draws only what the curr camera focuses on
       
        cls()
        background()

        -- music_update
            ptn=stat(24)--pattern id
            midx=stat(16)
            nptn=ptn0!=ptn
            ptn0=ptn

            ch1=stat(22)-- note number
            ch2=stat(21)-- note number
            ch1c=ch1!=ch1l
            ch2c=ch2!=ch2l
            if ch1c then 
                ch1h=ch1
                --ch1h2=ch1
                ch1l=ch1
            else
            ch1h+=(0.25)
            --ch1h2+=0.25
            end
            if ch2c then 
                --ch2h=ch2
                ch1h2=ch2
                ch2l=ch2
            else
            ch1h2+=(0.25)
           
            end

        --- 

       draw_stars()

        dust:draw()

        for e in all(entities) do e:draw() end
        for e in all(game.cur_level.entities) do e:draw() end
        
        
        player:draw()
        pal(15,0)
        map(game.cur_level.x0,game.cur_level.y0, game.cur_level.x0*8,game.cur_level.y0*8,
          1+(game.cur_level.x1-game.cur_level.x0),1+(game.cur_level.y1-game.cur_level.y0))
        pal()
        

    end

    main_draw_scene = function()
        for cam in all(cameras) do
            cam:draw()
            drawscreen()
        end
    end
    main_draw=main_draw_scene

    function _draw()
        main_draw()
        dialogues:draw()
        --pal(0,7)
        --print(seed,camera1.pos.x,camera1.pos.y)
        --pal()
    end
    function background()
        draw_bg()
    end
----------------------------------------

function _init()
    
    --make_soundtable()
    make_stars(level3,3,{'◆'})
    make_stars(level2,5,{'.'})
    make_stars(level4,20,{"★","."})
    music(0)

    spawn_gears()
    init_player1()
    spawn_objects()
    
    update_music_loop(level1)

    
end

function _update()
    story:update()

    for e in all(entities)do e:update()end
    for e in all(game.cur_level.entities)do e:update()end
    player:update()
    update_stars(player)

    --update_sound(player)

    c =(c+1) %30
    time = time%30 +1

    for cam in all(cameras) do cam:update() end
    dust:update()
    dialogues:updtexte()
    
    
end


__gfx__
000000009999999966666666cccccccc0000000000000000000000f0000000f0000000f0001111001111111166666667dddddddddddddddddddddddddddddddd
000000009000000966666666c000000c0000000000000000000000000000000000000000011661101111111106666670dddddddddddddddddddddddddddddddd
007007009000000966666666c000077c0000000000000000000000f0000000f0000000f0017b7b101111111100666700ddddddddddddd8ddddddd8ddddddd8dd
000770009000000966666666cccccccc000000000000000000000000000000000000000000e66e001111111100067000dddccddddddccddddddccddddddccddd
0007700090000009666666d1000000000000000000000000000000f0000000f000000000005550001111111100000000dddccddddddbcddddddacddddddc9ddd
00700700900050096ddddd51000000000000000000000000000000000000000000000000065550001111111100000000dddddddddddddddddddddddddddddddd
0000000090000009d555555100000000f0f0f0f000000000000000f0f0f0f000f0f0000000d0d0001111111100000000dddddddddddddddddddddddddddddddd
000000009999999911111111000000000000000000000000000000000000000000000000005050001111111100000000dddddddddddddddddddddddddddddddd
00000000000000cc0cccc0cc000000000000000000000000001111000011110000111100001111000000000066666667dddddddddddddddddddddddddddddddd
00000000cc0ccccc0cccc0cc000000000000d00000000000011661100116611001166110011661100000000006666670dddddddddddddddddddddddddddddddd
00000000cc0ccccc0cccc00000000000000d000000000000017b7b10017b7b10017b7b10016666100000000000666700dddddddddddddddddddddddddddddddd
00000000000000000cccc0cc00000000000d44400000000000e66e0000e66e0000e66e0000eeee000660666000067000dddccddddddccddddddccddddddccddd
00000000ccccc0cc0cccc0cc00000000000d000000000000005550006055500060555000005550006c06c0c600000000dddccddddddbcddddddacddddddc9ddd
00000000ccccc0cc000000cc000000000000d000000000000655506000555600005556000655500060cccc0600000000dddddddddddddddddddddddddddddddd
00000000ccccc0ccccccc0cc00000000000000000000000000d0500005d00d0000d0d00000d0d0006c0c60c600000000dddddddddddddddddddddddddddddddd
00000000ccccc0ccccccc0cc000000000000000000000000005000000000050000505000005050000666066000000000dddddddddddddddddddddddddddddddd
08888880ccccc0cccc000000000000000000000000000000055555000011110000111100001111000000000066666667dddddddddddddddddddddddddddddddd
08222220ccccc0cccc0ccccc099999900000000000000000055555500116611001166110011661100000000006666670dddddddddddddddddddddddddddddddd
00600600000000cccc0ccccc09999990000076000000000000444400017b7b10017b7b10017b7b100000000000666700dddddddddddddddddddddddddddddddd
0d7dd7d00cccc0cccc0ccccc09900990000067000000000000ffff0000e66e0000e66e0060e66e000000000000067000dddceddddddccddddddccddddddecddd
0dddddd00cccc0cccc0ccccc099009900000760000000000005550000055500000555000005550000000000000000000dddccddddddceddddddecddddddccddd
000000000cccc00000000000099999900000000000000000005550000655500000655000005555000000000000000000dddddddddddddddddddddddddddddddd
000000000cccc0ccccccc0cc0999999000000000000000000050d000000dd000000dd500000500500000000000000000dddddddddddddddddddddddddddddddd
000000000cccc0ccccccc0cc00000000000000000000000000002000005050000050000000d00d000000000000000000dddddddddddddddddddddddddddddddd
000000000000000000000000000000000000000000000000055555000011110000111100000000000000000000000000dddddddddddddddddddddddddddddddd
000000000000000000000000000000000000000000000000055555500116611001166110000000000000000000000000dddddddddddddddddddddddddddddddd
0000000000000000000000000000000000d600000000000000444400017b7b10017b7b10000000000000000000000000dddddddddddddddddddddddddddddddd
0dddddd000000000000000000000000000dd44400000000000ffff0000e66e0000e66e00000000000000000000000000dddcedddddd1cddddddc1ddddddecddd
0d7dd7d000006000000000000000000000d6000000000000005550000055500000555000000000000000000000000000ddd1cddddddceddddddecddddddc1ddd
006006000006060000000000000000000000000000000000005550000065500006555000000000000000000000000000dddddddddddddddddddddddddddddddd
02222280006000600000600000000000000000000000000000404000000dd000005dd000000000000000000000000000dddddddddddddddddddddddddddddddd
088888800600000600060600000000000000000000000000005050000005500000000500000000000000000000000000dddddddddddddddddddddddddddddddd
00000000000000000000200055556555dddddddd7dddddd7ddd66dddd444444d444444444dddd4dd664444446666666666666666666556666666666655555555
000000000000000000002000dd555551ddddddddd7dddd7ddd6666dd4111114499444555499994dd664155546666666666444446665555666777777666555566
000000000000000000002000ddd55d55dddddddddd7777ddddd7addd40000114dddddddd455554dd6641555466666666664777466667a6666700707666555566
000022222222000000002000d1154555dddddddddddddddddddaaddd40000014dddddddd4dddd4dd664111146666666666477746666aa6666777777666555566
000210000001200000002000d5155555ddddddddddddddddddda7ddd40000014dddddddd4dddd4dd668844446666666666400046666a76666666666666555566
0002000000002000000020001111555ddddddddddddddddddd6666dd40000014dddddddd499994dd664155546666666666400046665555666666666666555566
0002000000002000000020005151d555ddddddddddddddddddd66ddd40000014dddddddd455554dd664155546666666666444446666556666666666666555566
00020000000020000002220011115555dddddddddddddddddddddddd40000014dddddddd4dddd4dd664111146666666666666666666666666666666666555566
000200000000200000000000151555564444444415155d55dddddddd7dddddd77dddddd77dddddd7d444444d115dd65dd65dd65dd65dd6116655556666555566
00020000000020000000000011155d55994445555555d5d5dd4444ddd7dddd7d7ddddd7dd7ddddd7641555461666666666666666666666116655556666555566
00020000000020000000000251555555455554ddd1515d5dddd41ddddd7777dd7ddddd7dd7ddddd7641555461155565556555655565556116655556666555566
000210000001200022222222155555554dddd4dddd1555dddd4441ddddddddddd7ddd7dddd7ddd7d64111146115dd65dd65dd65dd65dd6116655556666555566
00002222222200000000000255d514554dddd4ddddddddddd444441ddddddddddd777dddddd777dd68844446115dd65dd65dd65dd65dd6116655556666555566
000000000000000000000000555555d5499994ddddddddddd664641dddddddddddd77dddddd77ddd641555461666666666666666666666116655556666555566
000000000000000000000000dd555515455554ddddddddddd444441ddddddddddd7dddddddddd7ddd415554d1155565556555655565556116655556666555566
000000000000000000000000555655654dddd4ddddddddddd144411ddddddddd7dddddddddddddd7d411114d115dd65dd65dd65dd65dd6116655556655555555
00000000000000000000000000000000000200000000000000000000000000000001dd000002dd000001dd000000000000000000000e0e0e00e0000000000000
0000000000000000000000000000000006666600000000000000000000000000000cdd00000cdd00500cdd0000000000000000000000000e00e0e00000000000
000000000000000000000000000000000d881d00ddddddddddddd000dddddddddddcdd00000cdddd62dddd0000266662000000000e0e0e0ee000e00000000000
666666666600000066666666660000000d88dd00dddddddddddddd00ddddddddddccdd00000ccddd6ddddd0000602606000000000e000e0000e0e0e000000000
dddddddddd000000dddddddddd0000000d881d00ccccddc1cccddd00cccccccccccdd0000000ccc16cccdd0000662606000000000e0e0e0000e000e000000000
d00000000d000000d00000000d0000000ddddd00000cdd0000ccdd00000000000000000000000000000cdd000060626600000000000e000ee0e0e0e000000000
d0bbbb0b0d000000d00000000d00000000d56000000cd200000cdd00000000000000000000000000000cdd000062622600000000000e0e00e000000000000000
d00000000d000000d00000000d0000000000000000066650000cdd00000000000000000000000000000cdd00002666620000000000000e00e0e0e00000000000
d0b0b0bb0d000000d00000000d00000000000000000000000001dd0000000000015ddd10000000000001dd000000000000000000000000000000000000000000
d00000000d000000d00000000d00000000ddd00000000000000cdd00000000000222221100000000000cdd050000000000000000000000000000000000000000
d66666666d000000d66666666d00000000db600000000000000cdd000000dddd266662ddddddddd1000cdd260000000000000000000000000000000000000000
dddcc1d8dd000000dddcc1d8dd0000000066600000000000000cdd00000ddddd616dd62dddddddd1000cddd60000000000000000000000000000000000000000
dddddddddd000000dddddddddd0000000001000000000000000cdd00000dccc1616d662dccccccc1000cddc60000000000000000000000000000000000000000
ddd9d2d5dd000000ddd9d2d5dd0000000005000000000000000cdd00000ccd006626562500000000000cdd0000d666666666666666667d000000000000000000
dddddddddd000000dddddddddd000000000d000000000000000cdd00000cdd006226262100000000000cdd000060000000000000000006000000000000000000
dddddddddd000000dddddddddd000000000dd667d66666bd000cdd00000cdd000666620000000000000cdd000060000000000000000006000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000001212121212121212121212000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000001200000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
12122112211222211221121212121212121212121212121222121212121212121212121212121212121212121200000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
21d2d2000000c3000000000000000000000000000000000022128600000000000000000000000000967676661200000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
12e200000000d30000000000000000000000e3000000000010100000000000000000000000000000000000671200000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
12e200000000000000f2d3e3e30000000000e3000000000010100000000000000000000000000000000000a61200000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1200000000f300c20000d300000000f30000c2c21212121222120000000000001313232313132323000000961200000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2100000000f2f200000000000000000000000000d3d3001222121212121212121212121212121221f30000f31212212112219797121212000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1200c200000000000000000000f2f200000000000000d21222000000000000000000000000967656977697768600000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
210000f3f3000000000000c30000000000e2e2000000f31222000000000000000000000000000067000000000000000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1200000000e3e30000d3000000000000d200000000c3001222000000000000000000000000000067000000000000000000000000000012000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
12c2c20000e3000000d3000000c2c200000000000000001222000000000000000000000000000067000000232312122323000000000012121212121212121200
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
12221212211212222112122212121212121212c1c1c1c11212121212121212121212121212121212121212121212121212121212121212d10000000000e11200
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
120077769776979776978612000000000000000000f0f00067876667969766f0f00000e0e00000d00000c0c0d0d00000e0e0f0f0000000000000000000002200
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1197860000000000000000210000000000000000e0f0f00067778696766667f0f00000e0e00000d00000c00000d00000e00000f0000000000000000000002200
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11000000000000000000000000000000000000e0e0f0f00096867797768667f0f00000e0e00000d00000c00000d00000e00000f0000000000000000000002200
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
210000009000000000000000b7d7b7d700d0d0d0e0f0f00000006700000067f0f00000e0e000212121d7c00000d0b7d7e0b7d7f0b7c712000000000000002200
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
12000000000000000000131012121212121212121212121212121212121212121212121212121212121212121212121212121212121212c10000000000f12200
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
21122121122222121221121200000000000000000000000000000000000000000000000012121212121212121212121212121212121212121212121212122200
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000ccccc0cccc000000ccccc0ccccccc1cc1cccc1ccccccc1ccccccc1cccc0111111cccc1ccccccc1ccccccc0cccc0100010001000100010
0000000000000000000ccccc0cccc0cccccccccc0ccccccc1cc1cccc1ccccccc1ccccccc1cccc1ccccc1cccc1ccccccc0ccccccc0cccc0ccccc0100010001000
0000000000000000000000000cccc0ccccc000000cc000111cc1cccc111111111cc111111cccc0ccccc1cccc111111111cc000000cccc0ccccc0001000100010
00000000000000000000cccc0cccc0ccccc0cccc0cc0cccc1cc1cccc1cc1cccc1cc1cccc1cccc1ccccc1cccc1cc1cccc1cc0cccc0cccc0ccccc0100010001000
00000000000000000000cccc0cccc0ccccc0cccc0cc0cccc1cc1cccc1cc1cccc1cc1cccc1cccc0ccccc1cccc1cc1cccc1cc0cccc0cccc0ccccc0001000100000
00000000000000000000cccc000000000000cccc0011cccc111111111cc1cccc1111cccc11111111111111111cc1cccc1110cccc001110001000100010001000
00000000000000000000cccc0ccccccc0cc0cccc1cc0cccc1ccccccc1cc1cccc1cc0cccc1ccccccc1ccccccc1cc0cccc1cc0cccc0ccccccc0cc0001000100000
00000000000000000000cccc0ccccccc0cc0cccc1cc1cccc1ccccccc1cc1cccc1cc1cccc1ccccccc1ccccccc1cc1cccc1cc1cccc1ccccccc1cc0100010001000
0000000000000000000ccccc0cc0000000000000111110111111101111111011111110111111111111111111111110111111101dd11ccccc0cc0000000000000
0000000000000000000ccccc0cc000000000000111111111111111111111111111111111111111111111111111111111111111cdd11ccccc1cc0000000000000
0000000000000000000000000cc000000000000ddddddddddddddddddd1ddddddddddddddd1ddddddd1ddddddddddddddd1dddcdd11100100cc0000000000000
00000000000000000000cccc0cc00000000000dddddddddddddddddddd1ddddddddddddddd1ddddddd1ddddddddddddddd1ddccdd111cccc1cc0000000000000
00000000000000000000cccc0cc00000000000dccc1ccccccccccccccc1ccccccccccccccc1ccccccc1ccccccccccccccc1cccdd1111cccc0cc0000000000000
00000000000000000000cccc00000000000001ccd1111111111111111111111111111111111111111111111111111111111111111111cccc1000000000000000
00000000000000000000cccc0cc00000000011cdd0111110101111101011111010111110101010111111111111111010101111111111cccc0cc0000000000000
00000000000000000000cccc0cc00000000011cdd1111111111111111111111111111111111111111111111111111111111111111111cccc1cc0000000000000
0000000000000000000000000cc000000000001dd1111111111111111111111111111011111110111111111111111011111110111111cccc0cc0000000000000
0000000000000000000cc0ccccc00000000001cdd1111111111111111111111111111111111111111111111111111111111111111111cccc1cc0000000000000
0000000000000000000cc0cccccddddddd1dddcdd1111111111111111111111111111011111110111111111111111011111110111111cccc0010000000000000
000000000000000000000000000ddddddd1ddccdd1111111111111111111111111111111111111111111111111111111111111111111cccc1cc0000000000000
0000000000000000000ccccc0ccccccccc1cccdd11111111111111111111111111111011111110111111111111111111111111111111cccc0cc0000000000000
0000000000000000000ccccc0cc11110000011111111111111111111111111111111111111111111111111111110001111111111111110001cc0000000000000
0000000000000000000ccccc1cc11110000011101010101111111110101010101010111111111010101010101000000010111111111ccccc0cc0000000000000
0000000000000000000ccccc1cc11111111111111111111111111111111111111111111111111111111111111000000011111111111ccccc1cc0000000000000
0000000000000000000111111cc11011111111111111101111111011111111111111101111111011111110111000000011111111111100100010000000000000
0000000000000000000cc1ccccc11111111111111111111111111111111111111111111111111111111111110000000001111111111100001000000000000000
0000000000000000000cc1ccccc11011111111111111101111111011111111111111101111111011111110110000000000000111111000000010000000000000
00000000000000000001111111111111111111111111111111111111111111111111111111111111111111110000000000000000100000000000000000000000
0000000000000000000ccccc1cc11011111111111111101111111011111111111111101111111011111111100000000000000000000000000010000000000000
0000000000000000000ccccc1cc11111111111111111111111111111111111111111111111111111111111000000000000000000000000000000000000000000
0000000000000000000ccccc1cc11010101010101010111111111011111111111111101111111010101100000000000000000000000000000010000000000000
0000000000000000000ccccc1cc11111111111111111111111111111111111111111111111111111111000000000000000000000000000000000000000000000
00000000000000000001cccc1cc11111111110111111111111111011111110111111101111111011110000000000000000000000000000000010000000000000
00000000000000000001cccc1cc11111111111111111111111111111111111111111111111110000000000000000000000000000000000001000000000000000
00000000000000000001cccc11111111111110111111111111111011111110111111101111100000000000000000000000000000000000000010000000000000
00000000000000000001cccc1cc11111111111111111111111111111111111111111111111000000000666666666600000000000000000000000000000000000
00000000000000000001cccc1cc11111111110111111111111111011111111111111101111000000000dddddddddd00000000000000000000010000000000000
0000000000000000000111111cc11111111111111111111111111111111111111111111111000000000d00000000d00000000000000000000000000000000000
0000000000000000000ccccc1cc01011111110101010101111111010101111101010111010100000000d0bbbb0b0d00000000000000000000000000000000000
0000000000000000000ccccc1cc11111111111111111111111100001111111111111111111110000000d00000000d00000000000000000000000000000000000
0000000000000000000ccccc1cc11011111111111111101111011110111111111111101111110000000d0b0b0bb0d00000000000000999999990000000000000
0000000000000000000ccccc1cc11ddd111111111111111110116611011111111111111111111000000d00000000d00000000000000900000090000010001000
0000000000000000000111111cc11d86111111111111101110170701011111111111101111111000000d66666666d00000000000000900000090000000100010
00000000000000000001cccc1cc116661111111111111111110e66e0111111111111111111111000000dddcc1d8dd00000000000000900000090000010001000
00000000000000000001cccc1cc11111111111111111111111055501111111111111101111111000000dddddddddd00000000006000900000090000000100010
00000000000000000001cccc11111151111111111111111110655501111111111111111111111000000ddd9d2d5dd00000000060600900050090000000001000
00000000000000000001cccc1cc111d11111111010111110100d0d00101010111111101010101000000dddddddddd00000000600060900000090000000100010
00000000000000000001cccc1cc111dd667d666668d1111111050501111111111111111111111000000dddddddddd00000006000006999999990000010001000
00000000000000000001cccc1ccccccc1cc1cccc1cc1cccc1ccccccc1cccc011111cc111111ccccc0ccccccc0cc0cccc0ccccccc0ccccccc0cc0000000100010
00000000000000000000cccc0ccccccc0cc0cccc0cc0cccc0ccccccc0cccc0ccccccc0cccccccccc0ccccccc0cc0cccc0ccccccc0ccccccc0cc0000000000000
00000000000000000000cccc000000000cc0cccc0000cccc000000000cccc0ccccccc0ccccc000000cc000000cc0cccc000000000cc000000cc0000000000000
00000000000000000000cccc0cc0cccc0cc0cccc0cc0cccc0cc0cccc0cccc0ccccccc0ccccc0cccc0cc0cccc0cc0cccc0cc0cccc0cc0cccc0cc0000000000000
00000000000000000000cccc0cc0cccc0cc0cccc0cc0cccc0cc0cccc0cccc0ccccccc0ccccc0cccc0cc0cccc0cc0cccc0cc0cccc0cc0cccc0cc0000000000000
0000000000000000000000000cc0cccc000000000cc000000cc0cccc00000000000000000000cccc0000cccc000000000cc0cccc0000cccc0000000000000000
0000000000000000000ccccc0cc0cccc0ccccccc0ccccccc0cc0cccc0ccccccc0ccccccc0cc0cccc0cc0cccc0ccccccc0cc0cccc0cc0cccc0cc0000000000000
0000000000000000000ccccc0cc0cccc0ccccccc0ccccccc0cc0cccc0ccccccc0ccccccc0cc0cccc0cc0cccc0ccccccc0cc0cccc0cc0cccc0cc0000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0005040500000000000000000000000000050500000000000000000000000000000505050000000000000000000000000000000000000000000000000000000005050005000000000102000000000000050500050300000000000000000100000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
050400202934303100031000310000000156450f1000f10009645096000310003100000000534303100031002d6502d6401563500000000000932309600096000065000630006150000000000006200062000615
010400202162521600156000310000000216000f1000f10009615216000310003100000001130003100031000962521600156000000000000093000960009600096150c6000c6000000000000006000060000600
050400201133303100031000310000000216450f1000f10029353216000310003100000001d3000310003100356551563515600000000000011353096000960000650006300061500000000001d6430062000615
95081f200000000000000000000500000000000000000005000000000000000000050000000000000000000500000000000000000005000000000500000000050000000000000000000500000000050000000005
030800201134315600113131160011313056000560005600116150000011615031000310005600056000560001343010000131305600013130000000000000001161500000116150000000000000000000000000
95081f200a3000a3000a300003000a3000a3000a300003000a3000a30000000000000000500005000000000000000000000000500000000050000500000000000000000000000050000000005000050000000000
0d1000000000000000000000000000000000000000000000000000000000000000000000000000000000000003230032200322003210032300322003220032101863513000130001300013000130001300013000
0f10000000000000000000000000000000000000000000000000000000000000000000000000000000000000012000120001200012000d2000120001200012001860013100131001310013100131001310013100
7b0800202d6451a2001a2001d2001d2001d2001f2001f200216001820018200182001a2001a2001a2001a200216251a2001a2001a2001a2001a2001d2001d2002160018200182001820016200162001620000000
139000200000000000000000000000000000000000000000000000000001114011100111001110011150000000000001000010000100001000010000100031000000000000041140411004110041100411500000
01040000216332160321633216032163321603216332160315633156031563315603156331560315633156032d6332d6032d6332d6032d6332d6032d6332d6032163321603216332160321633216032063321603
4b0820200000000005000000000000000000000000000000000000000500000112000520005200112001120000000000050000000000000000000000000000000000000005000000520005200052000000000000
610400200964321600156000310000000216000f1000f10015625216000310003100000001130003100031002162021610216150000000000093000960009600156000c6000c6000000000000006000060000600
ad08000000000000000000000000000000000000000000000000000000000050000000003000050a3000030000000000050000000000000000000500000000000000000000000050000000000000000000500000
490800200d2200d2300d2200d2200d2101120011200112000d2100d2100d2100d2100d2101120011200112000c2200c2300c2200c2200c2101120011200112000c2100c2100c2100c21018230052001120000200
49100000006100061500600000000000000000000000000000610006151d6001d6001d6001d6001d6001d60000610006151d6001d6001d6001d6001d6001d60000610006151d6001d6001d6001d6001d6001d600
010400002403124030240302401024010240100520005200052000520005200192001920005200240002400024000240002400019200192000520024000240002400024000240000000000000000000000000000
010400001f0311f0301f0101f0101f010052000520005200052000520019200192000520024000240002400024000240001920019200052002400024000240002400024000000000000000000000000000000000
010400002203122030220302201022010220100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010400001d0311d0301d0301d0101d0101d0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800000a3000a3000a300003000a3000a3000a300003000a3000a3000a300003000a3000a3000d300003000a3000a3000a300003000a3000a3000d300003000a3000a3000a300003000a3000a3000d30000300
05100020188701887018870188701887018870188701887018a7018a7018a7018a7018a7018a7018a7018a70188701887018870188701887018870188701887018a7018a7018a7018a7018a7018a7018a7018a70
011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
03 08094247
00 0a424047
01 01070b47
01 0c070347
00 0c070347
00 0c070547
00 0c070d47
01 01080f44
00 010f0844
01 0a464344
01 400f4304
01 15080344
01 40154344
02 42464344
01 01050444
00 01050444
00 41060709
02 41420504
00 41464b44

