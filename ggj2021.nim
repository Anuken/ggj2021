import ecs, presets/[basic, effects, content], math, random, quadtree, macros, strutils, bloom

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

const 
  scl = 64.0
  worldSize = 100
  tileSizePx = 32'f32
  pixelation = 2
  layerFloor = -10000000'f32
  shootPos = vec2(13, 30) / tileSizePx
  reload = 0.1
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
    Person = object
      flip: bool
      walk: float32
      shoot: float32
    Input = object
    Solid = object
    Bullet = object
      shooter: EntityId

makeContent:
  air = Block()
  floor = Block()
  wall = Block(solid: true)

defineEffects:
  circleBullet:
    draw("player".patch, e.x, e.y, z = layerBloom)
    #fillCircle(e.x, e.y, 10.px * e.fout, color = rgb(0.6, 0.6, 0.6), z = layerBloom)

var tiles = newSeq[Tile](worldSize * worldSize)

proc tile(x, y: int): Tile = 
  if x >= worldSize or y >= worldSize or x < 0 or y < 0: Tile(floor: blockFloor, wall: blockAir) else: tiles[x + y*worldSize]

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

template bullet(aid: EffectId, xp, yp: float32, rot: float32 = 0, col: Color = colorWhite) =
  let vel = vec2l(rot, 0.1)
  discard newEntityWith(Pos(x: xp, y: yp), Timed(lifetime: 4), Effect(id: aid, rotation: rot, color: col), Bullet(), Hit(w: 0.2, h: 0.2), Vel(x: vel.x, y: vel.y))

macro shoot(t: untyped, xp, yp, rot: float32) =
  let effectId = ident("effectId" & t.repr.capitalizeAscii)
  result = quote do:
    let vel = vec2l(`rot`, 0.1)
    discard newEntityWith(Pos(x: `xp`, y: `yp`), Timed(lifetime: 4), Effect(id: `effectId`, rotation: `rot`), Bullet(), Hit(w: 0.2, h: 0.2), Vel(x: vel.x, y: vel.y))

sys("init", [Main]):

  init:
    initContent()
    discard newEntityWith(Pos(x: worldSize/2, y: worldSize/2), Person(), Vel(), Hit(w: 0.4, h: 0.4), Solid(), Input())
    fau.pixelScl = 1.0 / tileSizePx

    for tile in tiles.mitems:
      tile.floor = blockFloor
      tile.wall = blockAir

      if rand(10) < 1: tile.wall = blockWall
  
sys("controlled", [Person, Input, Pos, Vel]):
  all:
    let v = vec2(axis(keyA, keyD), axis(KeyCode.keyS, keyW)).lim(1) * 6 * fau.delta
    item.vel.x += v.x
    item.vel.y += v.y
    item.person.shoot -= fau.delta

    if keyMouseLeft.down:
      if item.person.shoot <= 0:
        let offset = shootPos * vec2(-item.person.flip.sign, 1) + item.pos.vec2
        shoot(circleBullet, offset.x, offset.y, rot = offset.angle(mouseWorld()))
        item.person.shoot = reload

sys("animate", [Vel, Person]):
  all:
    if abs(item.vel.x) >= 0.001:
      item.person.flip = item.vel.x < 0
    
    if len(item.vel.x, item.vel.y) >= 0.01:
      item.person.walk += fau.delta
    else:
      item.person.walk = 0

sys("quadtree", [Pos, Vel, Bullet, Hit]):
  vars:
    tree: Quadtree[QuadRef]
  init:
    sys.tree = newQuadtree[QuadRef](rect(-0.5, -0.5, worldSize + 1, worldSize + 1))
  start:
    sys.tree.clear()
  all:
    sys.tree.insert(QuadRef(entity: item.entity, x: item.pos.x - item.hit.w/2.0, y: item.pos.y - item.hit.h/2.0, w: item.hit.w, h: item.hit.h))

sys("bulletMove", [Pos, Vel, Bullet]):
  all:
    item.pos.x += item.vel.x
    item.pos.y += item.vel.y

sys("bulletHitWall", [Pos, Vel, Bullet, Hit]):
  all:
    if collidesTiles(rectCenter(item.pos.x, item.pos.y, item.hit.w, item.hit.h), proc(x, y: int): bool = solid(x, y)):
      item.entity.delete()

sys("moveSolid", [Pos, Vel, Solid, Hit]):
  all:
    let delta = moveDelta(rectCenter(item.pos.x, item.pos.y, item.hit.w, item.hit.h), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
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
    bloom: Bloom
  init:
    sys.buffer = newFramebuffer()
    sys.bloom = newBloom()
  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    sys.buffer.resize(fau.width div pixelation, fau.height div pixelation)
    let 
      buf = sys.buffer
      bloom = sys.bloom

    buf.push()

    draw(100, proc() =
      buf.pop()
      buf.blitQuad()
    )

    drawLayer(layerBloom, proc() = bloom.capture(), proc() = bloom.render())

    for x, y, t in eachTile():
      draw(t.floor.name.patch, x, y, layerFloor)
       
      if t.wall.id != 0:
        let reg = t.wall.name.patch
        draw(reg, x, y - 0.5, -(y - 0.5), align = daBot)

sys("drawPerson", [Person, Pos]):
  all:
    var p = "player".patch
    if item.person.walk > 0:
      p = ("player_walk_" & $(((item.person.walk * 6) mod 4) + 1).int).patch
    draw(p, item.pos.x, item.pos.y - 4.px, z = -item.pos.y, align = daBot, width = p.widthf.px * -item.person.flip.sign)

makeEffectsSystem()

launchFau("ggj2021")
