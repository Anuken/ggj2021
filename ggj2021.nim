import ecs, presets/[basic, effects, content], math, random, quadtree, macros, strutils, sequtils, hashes

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas --max:2048")

const 
  scl = 64.0
  worldSize = 60
  tileSizePx = 32'f32
  pixelation = 2
  layerFloor = -10000000'f32
  shootPos = vec2(13, 30) / tileSizePx
  reload = 0.2
  layerBloom = 10'f32
  shadowColor = rgba(0, 0, 0, 0.2)
  layerShadow = layerFloor + 100
  playerHealth = 6
  layerCutscene = 240
  maxRats = 3
  bossHealth = 240'f32

type
  Block = ref object of Content
    solid: bool
    patches: seq[Patch]

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
    DrawShadow = object
    Input = object
    Solid = object
    Damage = object
      amount: float32
    Health = object
      amount: float32
      hit: float32
    Bullet = object
      shooter: EntityRef
      hitEffect: EffectId
      rotvel, acceleration: float32
    Eye = object
      time: float32
      rot: float32
    Enemy = object
    Rat = object
      flip: bool
    Animate = object
      time: float32
    
    Follower = object
    Circler = object

    Fear = object
      global: float32
      time: float32
      rage: bool
      f1, f2, f3, f4: float32
      phase: int
    Joy = object
      time: float32
    
    OnHit = object
      entity: EntityRef
    OnDead = object

makeContent:
  air = Block()
  floor = Block()
  wall = Block(solid: true)
  fence = Block(solid: true)
  fencel = Block(solid: true)
  fencer = Block(solid: true)
  darkfence = Block(solid: true)
  darkfencel = Block(solid: true)
  darkfencer = Block(solid: true)
  grass = Block()
  darkgrass = Block()
  tile = Block()

var rats: int = 0
var arena: bool
var didIntro = false
var showTime: float32
var won = false

Animate.onAdd: curComponent.time = rand(0.0..1.0).float32
Joy.onAdd: curComponent.time = rand(0.0..1.0).float32

defineEffects:
  playerBullet:
    fillCircle(e.x, e.y, 10.px, z = layerBloom, color = %"f3a0e1")
    fillCircle(e.x, e.y, 5.px, z = layerBloom, color = colorWhite)
  
  joyDeath(lifetime = 1.0):
    draw("joy1".patch, e.x, e.y, color = rgba(1, 1, 1, e.fout), z = -e.y, align = daBot)
    particles(e.id, 30, e.x, e.y, 90.px * e.fin):
      fillCircle(x, y, 8.px * e.fout, color = %"fff236")
    
  ratPoof(lifetime = 0.7):
    particles(e.id, 20, e.x, e.y, 90.px * e.fin):
      fillCircle(x, y, 7.px * e.fout, color = %"815796")
  
  death(lifetime = 1.0):
    particles(e.id, 30, e.x, e.y, 90.px * e.fin):
      fillCircle(x, y, 6.px * e.fout, color = %"ff8da3")
  
  fearDeath(lifetime = 10000.0):
    draw("fearsleep".patch, e.x, e.y - min(e.time.px * 3.0, 15.px), z = -e.y, align = daBot)

    draw("circle".patch, e.x, e.y - 3.px, z = layerShadow, width = 3.6, height = 0.645)
  
  hit(lifetime = 0.3):
    particles(e.id, 6, e.x, e.y, 70.px * e.fin):
      fillCircle(x, y, 3.px * e.fout, color = %"fff236")

  fearHit(lifetime = 0.3):
    particles(e.id, 6, e.x, e.y, 70.px * e.fin):
      fillCircle(x, y, 3.px * e.fout, color = %"ff55ff")
  
  flowerBullet:
    fillCircle(e.x, e.y, 10.px, z = layerBloom, color = %"f8cc55")
    fillCircle(e.x, e.y, 5.px, z = layerBloom, color = %"fff236")
  
  shadowBullet:
    fillCircle(e.x, e.y, 10.px, z = layerBloom, color = %"ff55ff")
    fillCircle(e.x, e.y, 5.px, z = layerBloom, color = %"ffc0ff")

  bolt:
    draw("bolt".patch, e.x, e.y, rotation = e.rotation + 45.rad)

  eyeBullet:
    fillCircle(e.x, e.y, 10.px, z = layerBloom, color = %"8c365d")
    fillCircle(e.x, e.y, 5.px, z = layerBloom, color = %"cc95ae")

  shoot(lifetime = 0.2):
    poly(e.x, e.y, 10, 13.px * e.fin, stroke = 4.px * e.fout + 0.3.px, color = %"f3a0e1")
  
  despawn(lifetime = 0.2):
    poly(e.x, e.y, 10, 10.px * e.fout, stroke = 4.px * e.fout + 0.5.px, color = %"f3a0e1")
  
  ratGet(lifetime = 3):
    let p = "rat_grab".patch
    var a = 1'f32
    let l = 3'f32
    if e.time > (l - 1):
      a = l - e.time
    draw(p, fau.cam.pos.x, fau.cam.pos.y - fau.cam.h + fau.cam.h * min(e.fin.powout(2) * 6.0, 1.0), height = fau.cam.h, width = p.widthf / p.heightf * fau.cam.h, color = alpha(a), z = layerCutscene)
  
  win(lifetime = 999999):
    #assume h<w
    let p = "win".patch
    let w = p.widthf / p.heightf * fau.cam.h
    fillRect(fau.cam.pos.x - fau.cam.w/2.0, fau.cam.pos.y - fau.cam.h/2.0, fau.cam.w, fau.cam.h, z = layerCutscene, color = alpha(min(e.time, 1.0)))
    draw(p, fau.cam.pos.x, fau.cam.pos.y, height = fau.cam.h, width = w, z = layerCutscene + 1, color = alpha(min(e.time, 1.0)))
    
  start(lifetime = 4):
    #assume h<w
    let p = "start".patch
    let w = p.widthf / p.heightf * fau.cam.h
    var a = 1.0
    let l = 4'f32
    if e.time > (l - 1):
      a = l - e.time
    
    fillRect(fau.cam.pos.x - fau.cam.w/2.0, fau.cam.pos.y - fau.cam.h/2.0, fau.cam.w, fau.cam.h, z = layerCutscene, color = alpha(a))
    draw(p, fau.cam.pos.x, fau.cam.pos.y, height = fau.cam.h, width = w, z = layerCutscene, color = alpha(a))

  flash(lifetime = 1):
    draw(fau.white, fau.cam.pos.x, fau.cam.pos.y, width = fau.cam.w, height = fau.cam.h, color = rgba(e.color.r, e.color.g, e.color.b, e.fout))

var tiles = newSeq[Tile](worldSize * worldSize)

proc tile(x, y: int): Tile = 
  if x >= worldSize or y >= worldSize or x < 0 or y < 0: Tile(floor: if not arena: blockGrass else: blockDarkgrass, wall: blockAir) else: tiles[x + y*worldSize]

proc setWall(x, y: int, wall: Block) = tiles[x + y*worldSize].wall = wall

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

macro shoot(t: untyped, ent: EntityRef, xp, yp, rot: float32, speed = 0.1, damage = 1'f32, rvel, accel: float32 = 0, life: float32 = 4) =
  let effectId = ident("effectId" & t.repr.capitalizeAscii)
  result = quote do:
    let vel = vec2l(`rot`, `speed`)
    discard newEntityWith(Pos(x: `xp`, y: `yp`), Timed(lifetime: `life`), Effect(id: `effectId`, rotation: `rot`), Bullet(shooter: `ent`, hitEffect: effectIdHit, rotvel: `rvel`, acceleration: `accel`), Hit(w: 0.2, h: 0.2), Vel(x: vel.x, y: vel.y), Damage(amount: `damage`))

template pitchRange(): float32 = rand(0.8..1.2).float32

template rect(pos: untyped, hit: untyped): Rect = rectCenter(pos.x + hit.x, pos.y + hit.y, hit.w, hit.h)

macro whenComp(entity: EntityRef, t: typedesc, body: untyped) =
  let varName = t.repr.toLowerAscii.ident
  result = quote do:
    if `entity`.alive and `entity`.hasComponent `t`:
      let `varName` {.inject.} = `entity`.fetchComponent `t`
      `body`

template clearAll(group: untyped) =
  while group.groups.len > 0:
    let item = group.groups[0]
    if item.entity.alive: item.entity.delete()

template makeArena() =
  for tile in tiles.mitems:
    tile.floor = blockDarkGrass
    tile.wall = blockAir
  
  fences(0, 0, worldSize - 1, worldSize - 1, blockDarkfence, blockDarkfencel, blockDarkfencer)
  arena = true

  clearAll(sysJoyBoss)
  clearAll(sysFearBoss)
  clearAll(sysRatmove)
  clearAll(sysBulletMove)

  #spawn boss
  discard newEntityWith(Pos(x: worldSize/2, y: worldSize/2 + 3), Fear(), Vel(), Hit(w: 2, h: 5.2, y: 3.5), Solid(), Health(amount: bossHealth), Animate(), Enemy())

template reset() =
  for tile in tiles.mitems:
    tile.floor = blockGrass
    tile.wall = blockAir
    
  let 
    inSize = 8
    cx = worldSize div 2
    corw = 17
  
  fences(cx - inSize, 0, inSize * 2, inSize * 2)
  fences(cx - inSize, worldSize - 1 - inSize * 2, inSize * 2, inSize * 2)
  fences(worldSize div 2 - corw, inSize * 2, corw * 2, worldSize - 1 - inSize * 4)

  for i in 1..<inSize*2:
    setWall(cx - inSize + i, inSize*2, blockAir)
    setWall(cx - inSize + i, worldSize - 1 - inSize*2, blockAir)

  clearAll(sysAll)

  #player
  discard newEntityWith(Pos(x: worldSize/2, y: 4), Person(), Vel(), Hit(w: 0.72, h: 1, y: 0.7), Solid(), Input(), Health(amount: playerHealth))

  rats = 0

  #rats
  for pos in [vec2(29, 15), vec2(30, 38), vec2(26, 57)]:
    discard newEntityWith(Pos(x: pos.x, y: pos.y), Rat(), Vel(), Hit(w: 13.px, h: 5.px), Solid(), Health(amount: 2), Animate(), Enemy())
    
  #flowers
  for pos in [vec2(34, 29), vec2(25, 53)]:
    discard newEntityWith(Pos(x: pos.x, y: pos.y), Joy(), Vel(), Hit(w: 2, h: 6, y: 3), Solid(), Health(amount: 15), Animate(), Enemy())

  #when defined(debug):
  #  makeArena()

  if not didIntro:
    #when not defined(debug):
    effectStart(0, 0)
    didIntro = true
  
  if arena:
    makeArena()

template fences(x, y: int, w, h: int, base = blockFence, left = blockFencel, right = blockFencer) =
  for i in 0..<h:
    setWall(x + w, i + y, left)
    setWall(x, i + y, right)

  for i in 1..<w:
    setWall(x + i, y, base)
    setWall(x + i, y + h, base)

sys("init", [Main]):
  vars:
    vgarden: Voice
    vboss: Voice

  init:
    fau.pixelScl = 1.0 / tileSizePx
    initContent()
    reset()

  start:
    showTime += fau.delta
    #if not defined(debug):
    sysControlled.paused = won or showTime < 4
    sysJoyBoss.paused = sysControlled.paused

    if not(arena) or won:
      sys.vboss.stop()
      if not sys.vgarden.valid:
        sys.vgarden = musicGarden.play(loop = true, volume = 1.2)
    else:
      sys.vgarden.stop()
      if not sys.vboss.valid:
        sys.vboss = musicGardenboss.play(loop = true)
    


sys("all", [Pos]):
  init:
    discard

sys("controlled", [Person, Input, Pos, Vel]):
  all:
    let v = vec2(axis(keyA, keyD), axis(KeyCode.keyS, keyW)).lim(1) * 6 * fau.delta
    item.vel.x += v.x
    item.vel.y += v.y
    item.person.shoot -= fau.delta

    if keyMouseLeft.down:
      if item.person.shoot <= 0:
        let offset = shootPos * vec2(-item.person.flip.sign, 1) + item.pos.vec2
        let ang = offset.angle(mouseWorld())
        shoot(playerBullet, item.entity, offset.x, offset.y, rot = ang, speed = 0.3, life = 0.84)
        item.person.shoot = reload
        effectShoot(offset.x, offset.y)
        item.person.flip = ang >= 90.rad and ang < 270.rad
        soundShoot.play(pitchRange, volume = 0.8)

sys("animatePerson", [Vel, Person]):
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

sys("collide", [Pos, Vel, Bullet, Hit]):
  vars:
    output: seq[QuadRef]
  all:
    sys.output.setLen(0)
    let r = rect(item.pos, item.hit)
    sysQuadtree.tree.intersect(r, sys.output)
    for elem in sys.output:
      if elem.entity != item.bullet.shooter and elem.entity != item.entity and elem.entity.alive and item.bullet.shooter.alive and not(elem.entity.hasComponent(Enemy) and item.bullet.shooter.hasComponent(Enemy)) and not elem.entity.hasComponent Rat:
        let 
          hitter = item.entity
          target = elem.entity
        
        whenComp(hitter, Damage):
          whenComp(target, Health):
            health.amount -= damage.amount
            health.hit = 1'f32

            let pos = hitter.fetchComponent Pos
            effectFearHit(pos.x, pos.y)

            if target.hasComponent Person:
              soundPlayerDamage.play(pitchRange)
            elif target.hasComponent Enemy:
              soundEnemyDamage.play(pitchRange)

            if health.amount <= 0:
              let tpos = target.fetchComponent Pos

              if target.hasComponent Joy: 
                effectJoyDeath(tpos.x, tpos.y)
                soundFlowerDeath.play()
              elif target.hasComponent Fear: 
                effectFearDeath(tpos.x, tpos.y)
                rats.inc
                won = true
                effectFlash(0, 0, col = colorWhite)
                soundRatDefeat.play()
                
                clearAll(sysBulletMove)
                clearAll(sysEye)
                target.delete()
                break
              elif target.hasComponent Person:
                effectDeath(tpos.x, tpos.y)
                reset()
                effectFlash(0, 0, life = 1.2)
                target.delete()
                break
              else: effectDeath(tpos.x, tpos.y)

              target.delete()
            hitter.delete()
            break

sys("won", [Main]):
  vars:
    time: float32
  start:
    if won:
      sys.time += fau.delta

    if sys.time >= 5:
      effectWin(0, 0)

sys("bulletMove", [Pos, Vel, Bullet]):
  all:
    item.pos.x += item.vel.x
    item.pos.y += item.vel.y
    var v = item.vel.vec2.rotate(item.bullet.rotvel * fau.delta)
    v.len = (v.len + item.bullet.acceleration * fau.delta)
    item.vel.x = v.x
    item.vel.y = v.y
    
sys("bulletEffect", [Pos, Vel, Bullet, Effect]):
  all:
    item.effect.rotation = item.vel.vec2.angle

sys("bulletHitWall", [Pos, Vel, Bullet, Hit]):
  all:
    if collidesTiles(rect(item.pos, item.hit), proc(x, y: int): bool = solid(x, y)):
      effectFearHit(item.pos.x, item.pos.y)
      item.entity.delete()

sys("moveSolid", [Pos, Vel, Solid, Hit]):
  all:
    let delta = moveDelta(rectCenter(item.pos.x, item.pos.y, 0.4, 0.2), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
    item.pos.x += delta.x
    item.pos.y += delta.y
    item.vel.x = 0
    item.vel.y = 0

sys("healthHitAnim", [Health]):
  all:
    item.health.hit -= fau.delta * 9
    if item.health.hit < 0: item.health.hit = 0

sys("animation", [Animate]):
  all:
    item.animate.time += fau.delta


sys("player", [Person, Input, Health, Pos]):
  vars:
    health: float32
    pos: Vec2
    cur: EntityRef
  start:
    if sys.groups.len == 0: sys.health = 0
  all:
    sys.health = item.health.amount
    sys.pos = item.pos.vec2
    sys.cur = item.entity

sys("eye", [Eye]): init: discard #storage for eye count

sys("follower", [Pos, Eye, Solid, Hit, Vel, Animate, Follower]):
  all:
    var r = initRand(item.entity.hash.int64)
    let off = vec2l((r.rand(360.0.rad).float32 + item.eye.rot), 6.0)
    let move = (sysPlayer.pos.vec2 - item.pos.vec2)
    let movenor = ((move + off).nor * 0.05)
    item.vel.x += movenor.x
    item.vel.y += movenor.y

    item.eye.time += fau.delta
    item.eye.rot += fau.delta
    if item.eye.time > 3.0:
      for i in 0..2:
        shoot(eyeBullet, item.entity, item.pos.x, item.pos.y, rot = move.angle, speed = 0.07 + i*0.02)
      item.eye.time = 0

sys("circler", [Pos, Eye, Solid, Hit, Vel, Animate, Circler]):
  all:
    var r = initRand(item.entity.hash.int64)
    let off = vec2l((r.rand(360.0.rad).float32 + item.eye.rot / 5.0), 20.0)
    let move = (vec2(worldSize / 2.0, worldSize / 2.0) - item.pos.vec2)
    let movenor = ((move + off).nor * 0.07)
    item.vel.x += movenor.x
    item.vel.y += movenor.y

    item.eye.time += fau.delta
    item.eye.rot += fau.delta
    if item.eye.time > 3.0:
      for i in 0..2:
        shoot(eyeBullet, item.entity, item.pos.x, item.pos.y, rot = item.pos.vec2.angle(sysPlayer.pos), speed = 0.07 + i*0.02)
      item.eye.time = 0

sys("ratmove", [Pos, Rat, Solid, Hit, Vel]):
  all:
    let move = vec2(sin(item.pos.y + item.pos.x / 10.0, 4, 2.0), sin(item.pos.x + item.pos.y / 30.0, 5.0, 3.0)).nor * 0.01 * 0.4
    item.vel.x += move.x
    item.vel.y += move.y
    item.rat.flip = move.x < 0.0

    if item.pos.vec2.within(sysPlayer.pos, 0.6):
      if rats != maxRats - 1:
        effectRatGet(item.pos.x, item.pos.y)
        effectRatPoof(item.pos.x, item.pos.y)
        soundRatPickup.play()
        item.entity.delete()
        rats.inc
      else:
        if sysPlayer.cur.alive:
          let pos = sysPlayer.cur.fetchComponent Pos
          pos.x = worldSize / 2.0
          pos.y = worldSize / 2.0 - 10
          item.entity.delete()
        
        effectFlash(0, 0, col = colorBlack, life = 3)
        makeArena()

sys("joyBoss", [Pos, Joy, Animate]):
  all:
    item.joy.time += fau.delta
    if item.joy.time > 3.0:
      circle(20):
        shoot(flowerBullet, item.entity, item.pos.x, item.pos.y + 166.px, rot = angle + item.animate.time / 3.0, speed = 0.07)
      
      item.joy.time = 0
      soundFlowerShoot.play(pitchRange)

sys("fearBoss", [Pos, Fear, Animate, Health, Vel]):
  all:
    item.fear.global += fau.delta

    let phases = 5
    let phase = max(phases - (item.health.amount / bossHealth * phases).int, 1)
    let pos = vec2(item.pos.x + 4.px, item.pos.y + 139.px)

    if phase != item.fear.phase:
      item.fear.phase = phase
      soundRatPhase.play()
      if phase == 5:
        effectFlash(0, 0, col = %"ffc0ff")
        soundRatRage.play()
        item.fear.rage = true

    template every(delay: float32, vname: untyped, code: untyped) =
      item.fear.vname += fau.delta
      if item.fear.vname >= delay:
        code
        item.fear.vname = 0

    template every(delay: float32, code: untyped) =
      every(delay, time): 
        code

    template bullet(btype: untyped, ang: float32, rotv: float32 = 0.0, vel: float32 = 0.1, acc: float32 = 0.0) =
      shoot(btype, item.entity, pos.x, pos.y, rot = ang, rvel = rotv, speed = vel, accel = acc)
    
    template makeEye(ai: untyped) = discard newEntityWith(Pos(x: item.pos.x + rand(-0.2..0.2), y: item.pos.y + 1 + rand(-0.2..0.2)), Vel(), Hit(w: 24.px, h: 24.px, y: 12.px), Solid(), Health(amount: 2), Animate(), Eye(), Enemy(), ai())

    case phase:
    of 1:
      every(0.3):
        circle(4):
          bullet(shadowBullet, angle + item.animate.time / 4.0, -0.3 * (item.fear.f2.int mod 2 == 0).sign)
        item.fear.f2 += 1
    of 2:
      if (item.fear.global / 5).int mod 2 == 0:
        item.fear.f1 += fau.delta
      else:
        item.fear.f1 -= fau.delta

      every 0.12:
        circle(3):
          bullet(shadowBullet, angle + item.fear.f1 / 1.3, 0.4, 0.09 + (item.fear.f2 mod 3) / 3 * 0.05)
        item.fear.f2 += 1
    of 3:
      every 7, f1:
        var count = 0
        while sysEye.groups.len < 8 and count < 2: 
          makeEye(Follower)
          count.inc
      every 1.2:
        item.fear.f3 += 1
        for i in 0..2:
          circle(3):
            let m = (item.fear.f3.int mod 2)
            bullet(shadowBullet, angle + m * 2.0 + i / 6.0, 1.0 * (m == 0).sign, 0.1 + i / 3.0 * 0.06)
        
      every 1.3, f2:
        let base = pos.angle(sysPlayer.pos)
        for i in -2..2:
          bullet(shadowBullet, base + i * 0.09, -1.0 * i)
    of 5:
      if (item.fear.global / 4).int mod 2 == 0:
        item.fear.f3 += fau.delta
      else:
        item.fear.f3 -= fau.delta
      
      let v = vec2(vec2(worldSize / 2, worldSize / 2) - item.pos.vec2).lim(0.02)
      item.vel.x += v.x
      item.vel.y += v.y

      every 11, f1:
        var count = 0
        while sysEye.groups.len < 10 and count < 2: 
          makeEye(Circler)
          count.inc
      every 0.21:
        for i in 0..3:
          circle(3):
            bullet(shadowBullet, angle + item.fear.f3 / 2.8, i / 3.0 * 2.0, 0.02 + i / 3.0 * 0.00, 0.06)
    of 4:
      let v = vec2(sin(item.pos.y, 3.6, 1), sin(item.pos.x, 3.6, 1)).lim(0.02)
      item.vel.x += v.x
      item.vel.y += v.y

      every 4, f1:
        var count = 0
        while sysEye.groups.len < 8 and count < 1: 
          makeEye(Circler)
          count.inc
      every 0.4:
        let ang = pos.angle(sysPlayer.pos)
        for i in -2..1:
          bullet(shadowBullet, ang - i * 30.rad, i / 2.0, 0.1, 0.06)
    else:
      discard

sys("timedEffect", [Timed, Pos]):
  all:
    item.timed.time += fau.delta
    if item.timed.time >= item.timed.lifetime:
      item.timed.time = item.timed.lifetime
      
      if item.entity.hasComponent Bullet:
        effectDespawn(item.pos.x, item.pos.y)
      
      item.entity.delete()

sys("followCam", [Pos, Input]):
  all:
    fau.cam.pos = vec2(item.pos.x, item.pos.y + 42.px)
    fau.cam.pos += vec2((fau.widthf mod scl) / scl, (fau.heightf mod scl) / scl) * fau.pixelScl

sys("draw", [Main]):
  vars:
    buffer: Framebuffer
    shadows: Framebuffer
    healthf: float32
  init:
    sys.buffer = newFramebuffer()
    sys.shadows = newFramebuffer()

    #load all block textures before rendering
    for b in blockList:
      var maxFound = 0
      for i in 1..12:
        if not fau.atlas.patches.hasKey(b.name & $i): break
        maxFound = i
      
      if maxFound == 0:
        if fau.atlas.patches.hasKey(b.name):
          b.patches = @[b.name.patch]
      else:
        b.patches = (1..maxFound).toSeq().mapIt((b.name & $it).patch)
    
  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    sys.buffer.resize(fau.width div pixelation, fau.height div pixelation)
    sys.shadows.resize(sys.buffer.width, sys.buffer.height)
    let 
      buf = sys.buffer
      shadows = sys.shadows

    buf.push()

    draw(100, proc() =
      buf.pop()
      buf.blitQuad()
    )

    drawLayer(layerShadow, proc() = shadows.push(colorClear), proc() =
      shadows.pop()
      shadows.blit(color = shadowColor)
    )

    sys.healthf = sys.healthf.lerp(sysPlayer.health, 0.1)
    let healthf = sys.healthf

    #ui
    draw(200, proc() =
      drawMat ortho(0, 0, fau.width, fau.height)

      let 
        w = 300'f32
        h = 40'f32
        pad = 8'f32
      fillRect(0, 0, w + pad*2, h + pad*2, color = %"382b8f")
      fillRect(pad, pad, w, h, color = rgba(0, 0, 0, 1))
      fillRect(pad, pad, w * healthf / playerHealth, h, color = rgba(1, 0, 0, 1))

      fau.cam.use()
    )

    for x, y, t in eachTile():
      let r = hashInt(x + y * worldSize)
      draw(t.floor.patches[r mod t.floor.patches.len], x, y, layerFloor)
       
      if t.wall.id != 0:
        let reg = t.wall.name.patch
        draw(reg, x, y - 0.5, -(y - 0.5), align = daBot)

proc frame(pre: string, time, speed: float32): string = pre & $([1, 2, 3, 2][((time * speed) mod 4).int])

sys("drawEye", [Eye, Pos, Animate, Health]):
  all:
    draw(frame("eye", item.animate.time, 4).patch, item.pos.x, item.pos.y + 5.px, align = daBot, z = -item.pos.y, mixColor = rgba(1, 1, 1, 0).mix(colorWhite, item.health.hit))

sys("drawRat", [Rat, Pos]):
  all:
    draw("rat".patch, item.pos.x, item.pos.y - 4.px, align = daBot, z = -item.pos.y, width = "rat".patch.widthf.px * item.rat.flip.sign)

sys("drawFear", [Fear, Pos, Animate, Health]):
  all:
    let si = item.animate.time.sin(2, 15.px).abs
    draw(frame("fear" & (if item.fear.rage: "f" else: ""), item.animate.time, 4).patch, item.pos.x, item.pos.y - 6.px, align = daBot, z = -item.pos.y, mixColor = rgba(1, 1, 1, 0).mix(colorWhite, item.health.hit))

sys("drawJoy", [Joy, Pos, Animate, Health]):
  all:
    draw(frame("joy", item.animate.time, 5).patch, item.pos.x, item.pos.y - 6.px, align = daBot, z = -item.pos.y, mixColor = rgba(1, 1, 1, 0).mix(colorWhite, item.health.hit))

sys("drawShadow", [Pos, Solid, Hit]):
  all:
    draw("circle".patch, item.pos.x, item.pos.y - 3.px, z = layerShadow, width = item.hit.w * 1.8'f32, height = 10.px + item.hit.w / 6.0)

sys("drawPerson", [Person, Pos, Health]):
  all:
    var p = if keyMouseLeft.down: "player_attack_1".patch else: "player".patch
    if item.person.walk > 0:
      p = frame((if keyMouseLeft.down: "player_attack_" else: "player_walk_"), item.person.walk, 6).patch
    draw(p, item.pos.x, item.pos.y, align = daBot, width = p.widthf.px * -item.person.flip.sign, z = -item.pos.y, mixColor = rgba(1, 1, 1, 0).mix(colorWhite, item.health.hit))

makeEffectsSystem()

launchFau("ggj2021")
