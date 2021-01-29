import ecs, presets/[basic, effects, content], math, random

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

type
  Block = ref object of Content
    solid: bool

  Tile = object
    floor: Block
    wall: Block

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

makeContent:
  air = Block()
  floor = Block()
  wall = Block(solid: true)

const 
  scl = 80.0
  worldSize = 100
  tileSizePx = 32'f32
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

sys("animate", [Vel, Person]):
  all:
    if abs(item.vel.x) >= 0.001:
      item.person.flip = item.vel.x < 0
    
    if len(item.vel.x, item.vel.y) >= 0.01:
      item.person.walk += fau.delta
    else:
      item.person.walk = 0

sys("moveSolid", [Pos, Vel, Solid]):
  all:
    let delta = moveDelta(rectCenter(item.pos.x, item.pos.y, item.solid.w, item.solid.h), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
    item.pos.x += delta.x
    item.pos.y += delta.y
    item.vel.x = 0
    item.vel.y = 0

sys("followCam", [Pos, Input]):
  all:
    fau.cam.pos = vec2(item.pos.x, item.pos.y)
    fau.cam.pos += vec2((fau.widthf mod scl) / scl, (fau.heightf mod scl) / scl) * fau.pixelScl

sys("draw", [Main]):
  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

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

launchFau("ggj2021")
