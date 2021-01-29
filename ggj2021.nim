import ecs, presets/[basic, effects, content], math, random, quadtree

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

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
    Solid = object
      w, h: float32
    Person = object
      flip: bool
      walk: float32
    Input = object
    Bullet = object
      shooter: EntityId
      s: float32

makeContent:
  air = Block()
  floor = Block()
  wall = Block(solid: true)

defineEffects:
  circleBullet:
    fillCircle(e.x, e.y, 10.px * e.fout, color = colorWhite, z = 0)

const 
  scl = 64.0 + 32.0
  worldSize = 100
  tileSizePx = 32'f32
  pixelation = 3
  layerFloor = -10000000'f32

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
  discard newEntityWith(Pos(x: xp, y: yp), Timed(lifetime: 4), Effect(id: aid, rotation: rot, color: col), Bullet(s: 0.3), Vel(x: vel.x, y: vel.y))

sys("init", [Main]):

  init:
    initContent()
    discard newEntityWith(Pos(x: 10, y: 10), Person(), Vel(), Solid(w: 0.4, h: 0.4), Input())
    fau.pixelScl = 1.0 / tileSizePx

    for tile in tiles.mitems:
      tile.floor = blockFloor
      tile.wall = blockAir

      if rand(10) < 1: tile.wall = blockWall
  

sys("controlled", [Person, Input, Pos, Vel]):
  all:
    let v = vec2(axis(keyA, keyD), axis(KeyCode.keyS, keyW)).lim(1) * 5 * fau.delta
    item.vel.x += v.x
    item.vel.y += v.y

    if keyMouseLeft.tapped:
      bullet(effectIdCircleBullet, item.pos.x, item.pos.y, rot = item.pos.vec2.angle(mouseWorld()))

sys("animate", [Vel, Person]):
  all:
    if abs(item.vel.x) >= 0.001:
      item.person.flip = item.vel.x < 0
    
    if len(item.vel.x, item.vel.y) >= 0.01:
      item.person.walk += fau.delta
    else:
      item.person.walk = 0

sys("quadtree", [Pos, Vel, Bullet]):
  vars:
    tree: Quadtree[QuadRef]
  init:
    sys.tree = newQuadtree[QuadRef](rect(-0.5, -0.5, worldSize + 1, worldSize + 1))
  start:
    sys.tree.clear()
  all:
    sys.tree.insert(QuadRef(entity: item.entity, x: item.pos.x - item.bullet.s/2.0, y: item.pos.y - item.bullet.s/2.0, w: item.bullet.s, h: item.bullet.s))

sys("bulletMove", [Pos, Vel, Bullet]):
  all:
    item.pos.x += item.vel.x
    item.pos.y += item.vel.y

sys("moveSolid", [Pos, Vel, Solid]):
  all:
    let delta = moveDelta(rectCenter(item.pos.x, item.pos.y, item.solid.w, item.solid.h), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
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
  init:
    sys.buffer = newFramebuffer()
  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    sys.buffer.resize(fau.width div pixelation, fau.height div pixelation)
    let buf = sys.buffer

    buf.push()

    draw(1, proc() =
      buf.pop()
      buf.blitQuad()
    )

    for x, y, t in eachTile():
      draw(t.floor.name.patch, x, y, layerFloor)
       
      if t.wall.id != 0:
        let reg = t.wall.name.patch
        draw(reg, x, y - 0.5, -(y - 0.5), align = daBot)

sys("drawPerson", [Person, Pos]):
  all:
    var p = "char".patch
    if item.person.walk > 0:
      p = ("charwalk" & $(((item.person.walk * 7) mod 4) + 1).int).patch
    draw(p, item.pos.x, item.pos.y - 4.px, z = -item.pos.y, align = daBot, width = p.widthf.px * -item.person.flip.sign)

makeEffectsSystem()

launchFau("ggj2021")
