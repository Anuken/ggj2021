import ecs, presets/[basic, effects, content], math, random, quadtree, macros, strutils, bloom

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

const 
  scl = 64.0
  worldSize = 40
  tileSizePx = 32'f32
  pixelation = 2
  layerFloor = -10000000'f32
  shootPos = vec2(13, 30) / tileSizePx
  reload = 0.2
  layerBloom = 10'f32

type
  Block = ref object of Content
    solid: bool

  Tile = object
    floor: Block
    wall: Block
  
  QuadRef = object
    entity: EntityRef
    x, y, w, h: float32

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y: float32
    Hit = object
      w, h: float32
      x, y: float32
    Person = object
      flip: bool
      walk: float32
      shoot: float32
    Input = object
    Solid = object
    Damage = object
      amount: float32
    Health = object
      amount: float32
    Bullet = object
      shooter: EntityRef
    Anger = object
    Sadness = object
    Fear = object
    Happiness = object
    OnHit = object
      entity: EntityRef
    OnDead = object

makeContent:
  air = Block()
  floor = Block()
  wall = Block(solid: true)

defineEffects:
  circleBullet:
    fillPoly(e.x, e.y, 4, 10.px, z = layerBloom, rotation = e.fin * 360.0, color = rgba(1.0, 0.5, 0.5))
  
  death(lifetime = 0.5):
    particles(e.id, 10, e.x, e.y, 60.px * e.fin):
      fillCircle(x, y, 5.px * e.fout, color = rgba(1, 0, 0))
  
  hit(lifetime = 0.3):
    particles(e.id, 6, e.x, e.y, 70.px * e.fin):
      fillCircle(x, y, 3.px * e.fout, color = rgba(1, 1, 0))

var tiles = newSeq[Tile](worldSize * worldSize)

proc tile(x, y: int): Tile = 
  if x >= worldSize or y >= worldSize or x < 0 or y < 0: Tile(floor: blockFloor, wall: blockWall) else: tiles[x + y*worldSize]

proc solid(x, y: int): bool = tile(x, y).wall.solid

iterator eachTile*(): tuple[x, y: int, tile: Tile] =
  const pad = 2
  let 
    xrange = (fau.cam.w / 2).ceil.int + pad
    yrange = (fau.cam.h / 2).ceil.int + pad
    camx = fau.cam.pos.x.ceil.int
    camy = fau.cam.pos.y.ceil.int

  for cx in -xrange..xrange:
    for cy in -yrange..yrange:
      let 
        wcx = camx + cx
        wcy = camy + cy
      
      yield (wcx, wcy, tile(wcx, wcy))

macro shoot(t: untyped, ent: EntityRef, xp, yp, rot: float32, damage = 1'f32) =
  let effectId = ident("effectId" & t.repr.capitalizeAscii)
  result = quote do:
    let vel = vec2l(`rot`, 0.1)
    discard newEntityWith(Pos(x: `xp`, y: `yp`), Timed(lifetime: 4), Effect(id: `effectId`, rotation: `rot`), Bullet(shooter: `ent`), Hit(w: 0.2, h: 0.2), Vel(x: vel.x, y: vel.y), Damage(amount: `damage`))

template rect(pos: untyped, hit: untyped): Rect = rectCenter(pos.x + hit.x, pos.y + hit.y, hit.w, hit.h)

sys("init", [Main]):

  init:
    initContent()
    #player
    discard newEntityWith(Pos(x: worldSize/2, y: worldSize/2), Person(), Vel(), Hit(w: 0.4, h: 0.4), Solid(), Input(), Health(amount: 5))
    #anger
    discard newEntityWith(Pos(x: worldSize/2, y: worldSize/2 + 3), Anger(), Vel(), Hit(w: 3, h: 8, y: 4), Solid(), Health(amount: 5))

    fau.pixelScl = 1.0 / tileSizePx

    for tile in tiles.mitems:
      tile.floor = blockFloor
      tile.wall = blockAir

      #if rand(10) < 1: tile.wall = blockWall
  
sys("controlled", [Person, Input, Pos, Vel]):
  all:
    let v = vec2(axis(keyA, keyD), axis(KeyCode.keyS, keyW)).lim(1) * 6 * fau.delta
    item.vel.x += v.x
    item.vel.y += v.y
    item.person.shoot -= fau.delta

    if keyMouseLeft.down:
      if item.person.shoot <= 0:
        let offset = shootPos * vec2(-item.person.flip.sign, 1) + item.pos.vec2
        shoot(circleBullet, item.entity, offset.x, offset.y, rot = offset.angle(mouseWorld()))
        item.person.shoot = reload

sys("animate", [Vel, Person]):
  all:
    if abs(item.vel.x) >= 0.001:
      item.person.flip = item.vel.x < 0
    
    if len(item.vel.x, item.vel.y) >= 0.01:
      item.person.walk += fau.delta
    else:
      item.person.walk = 0

sys("quadtree", [Pos, Vel, Hit]):
  vars:
    tree: Quadtree[QuadRef]
  init:
    sys.tree = newQuadtree[QuadRef](rect(-0.5, -0.5, worldSize + 1, worldSize + 1))
  start:
    sys.tree.clear()
  all:
    sys.tree.insert(QuadRef(entity: item.entity, x: item.pos.x - item.hit.w/2.0 + item.hit.x, y: item.pos.y - item.hit.h/2.0 + item.hit.y, w: item.hit.w, h: item.hit.h))

#TODO only 1 collision per frame
sys("collide", [Pos, Vel, Bullet, Hit]):
  vars:
    output: seq[QuadRef]
  all:
    sys.output.setLen(0)
    let r = rect(item.pos, item.hit)
    sysQuadtree.tree.intersect(r, sys.output)
    for elem in sys.output:
      if elem.entity != item.bullet.shooter and elem.entity != item.entity and elem.entity.valid and elem.entity.hasComponent Health:
        elem.entity.addOrUpdate OnHit(entity: item.entity)
        
        break

#TODO only 1 hit per frame, bad handling
sys("healthHit", [Health, OnHit]):
  all:
    if item.onHit.entity.hasComponent Damage:
      item.health.amount -= item.onHit.entity.fetchComponent(Damage).amount
      let pos = item.onHit.entity.fetchComponent Pos
      effectHit(pos.x, pos.y)
      if item.health.amount <= 0:
        item.entity.addOrUpdate OnDead()
      item.onHit.entity.delete()
    
    item.entity.removeComponent OnHit

#TODO only 1 per frame
sys("kill", [Health, OnDead, Pos]):
  all:
    effectDeath(item.pos.x, item.pos.y)
    item.entity.delete()

sys("bulletMove", [Pos, Vel, Bullet]):
  all:
    item.pos.x += item.vel.x
    item.pos.y += item.vel.y

sys("bulletHitWall", [Pos, Vel, Bullet, Hit]):
  all:
    if collidesTiles(rect(item.pos, item.hit), proc(x, y: int): bool = solid(x, y)):
      item.entity.delete()

sys("moveSolid", [Pos, Vel, Solid, Hit]):
  all:
    let delta = moveDelta(rect(item.pos, item.hit), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
    item.pos.x += delta.x
    item.pos.y += delta.y
    item.vel.x = 0
    item.vel.y = 0

makeTimedSystem()

sys("followCam", [Pos, Input]):
  all:
    fau.cam.pos = vec2(item.pos.x, item.pos.y)
    fau.cam.pos += vec2((fau.widthf mod scl) / scl, (fau.heightf mod scl) / scl) * fau.pixelScl

sys("draw", [Main]):
  vars:
    buffer: Framebuffer
    #bloom: Bloom
  init:
    sys.buffer = newFramebuffer()
    #sys.bloom = newBloom()
  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    sys.buffer.resize(fau.width div pixelation, fau.height div pixelation)
    let 
      buf = sys.buffer
      #bloom = sys.bloom

    buf.push()

    draw(100, proc() =
      buf.pop()
      buf.blitQuad()
    )

    #drawLayer(layerBloom, proc() = bloom.capture(), proc() = bloom.render())

    for x, y, t in eachTile():
      draw(t.floor.name.patch, x, y, layerFloor)
       
      if t.wall.id != 0:
        let reg = t.wall.name.patch
        draw(reg, x, y - 0.5, -(y - 0.5), align = daBot)

sys("drawAnger", [Anger, Pos]):
  all:
    draw("anger1".patch, item.pos.x, item.pos.y, align = daBot, z = -item.pos.y)

sys("drawPerson", [Person, Pos]):
  vars:
    shader: Shader
  init:
    sys.shader = newShader(defaultBatchVert, 
    """
    varying lowp vec4 v_color;
    varying lowp vec4 v_mixcolor;
    varying vec2 v_texc;
    uniform sampler2D u_texture;
    void main(){
      vec4 c = texture2D(u_texture, v_texc);
      gl_FragColor = v_color * mix(c, vec4(v_mixcolor.rgb, c.a), v_mixcolor.a);
    }
    """)
  all:
    
    var p = if keyMouseLeft.down: "player_attack_1".patch else: "player".patch
    if item.person.walk > 0:
      p = ((if keyMouseLeft.down: "player_attack_" else: "player_walk_") & $(((item.person.walk * 6) mod 4) + 1).int).patch
    let
      x = item.pos.x
      y = item.pos.y - 4.px
      width = p.widthf.px * -item.person.flip.sign
      shader = sys.shader
    draw(-item.pos.y, proc() =
      withShader(shader):
        draw(p, x, y, align = daBot, width = width)
    )
    

makeEffectsSystem()

launchFau("ggj2021")
