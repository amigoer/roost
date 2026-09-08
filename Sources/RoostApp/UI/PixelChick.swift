import AppKit
import RoostCore

/// What the chick's face is saying.
enum MascotFace: String, CaseIterable, Sendable {
    /// Working: plain eyes, no badge, a hop.
    case running
    /// Stopped on something only a person can answer: wide eyes, amber "?".
    case waiting
    /// A tool that will not finish: squint, sweat drop, red "!".
    case stalled
    /// Turn ended: happy eyes, green tick.
    case done
    /// Something failed: crossed eyes, red "x".
    case error
    /// Nothing to report: closed eyes, grey "z", grey body.
    case idle
    /// The quota window is spent: grey body, red bar, eyes open.
    ///
    /// No new ink, only a combination none of the others use. Grey says nothing
    /// is moving, red says it matters, and the two together are the one thing
    /// neither `idle` nor `stalled` can say: awake, and walled in until a clock
    /// says otherwise.
    case spent
}

/// The mascot art, drawn from an editable grid.
///
/// Each frame is 15x12 cells: the chick fills the left 11 columns and the badge
/// sits in the top-right corner, so the body stays put from face to face and
/// only the corner changes. `B` body, `K` beak and feet, `E` eye, `A` badge,
/// `S` sweat drop, `.` transparent.
///
/// A face is a pose with a badge laid over it, and the two are written as
/// separate grids rather than one: the tick's arm reaches back into the body's
/// columns, and a badge that has to dodge the body is a badge drawn once per
/// pose it might appear on. Composed, every face's resting frame is exactly
/// what it always was, which is what keeps the still exports honest.
enum PixelChick {
    static let columns = 15
    /// The chick alone. The remaining columns are the badge's, and they are
    /// empty in some faces, so this is what has to stay put from face to face.
    static let bodyColumns = 11
    static let rows = 12
    /// A spare row above the grid, so a hop has somewhere to go. Downward
    /// motion needs no such room: every pose leaves its bottom row empty.
    static let hopRoom = 1

    // MARK: - Poses

    /// What the body is doing, badge column left blank.
    ///
    /// One silhouette runs through all of them, because the chick is not a
    /// different chick when it is tired. What changes is the eyes, the beak,
    /// the legs, and -- once, on landing -- a row of height.
    enum Pose {
        /// Eyes open, feet down. Everything else is a departure from this.
        static let stand = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBEBBBEBB.....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        /// Lids down. A tenth of a second of this is a blink; held, it is
        /// asleep, which is why `idle` needs no pose of its own.
        static let shut = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "BBEEBKBEEBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        /// Eyes twice the size, which is the whole difference between watching
        /// something and waiting to be answered.
        static let wide = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BEEBBBEEB.....",
            "BBEEBKBEEBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        /// Beak open. A cheep, which is what the island is doing anyway.
        static let peep = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBEBBBEBB.....",
            "BBBEBKBEBBB....",
            "BBBBKKKBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        static let widePeep = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BEEBBBEEB.....",
            "BBEEBKBEEBB....",
            "BBBBKKKBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        static let happy = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBEBBBEBB.....",
            "BBEBEKEBEBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        static let happyPeep = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBEBBBEBB.....",
            "BBEBEKEBEBB....",
            "BBBBKKKBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        static let crossed = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BEBBBBBEB.....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        /// Squinting, with nothing on its cheek yet.
        static let dry = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        /// The drop, at the three heights it falls through. It skips the two
        /// rows where the body is at its widest, which is what makes it read
        /// as falling past rather than sliding down.
        static let dripHigh = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBBS....",
            ".BBBBBBBBBS....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        static let dripMid = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBBS....",
            ".BBBBBBBBBS....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "...............",
        ]

        static let dripLow = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB..S....",
            "....K.K...S....",
            "...............",
        ]

        /// A row shorter and standing wider: the frame a hop is wound up on,
        /// and the frame it lands into.
        static let crouch = [
            "...............",
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBEBBBEBB.....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "...K...K.......",
            "...............",
        ]

        /// Legs folded up under it. Off the ground.
        static let airborne = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBEBBBEBB.....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "...............",
            "...............",
        ]

        /// Legs hanging. The top of the hop, where nothing else is happening.
        static let dangle = [
            "...BBBBB.......",
            "..BBBBBBB......",
            ".BBBBBBBBB.....",
            ".BBEBBBEBB.....",
            "BBBEBKBEBBB....",
            "BBBBBKBBBBB....",
            ".BBBBBBBBB.....",
            ".BBBBBBBBB.....",
            "..BBBBBBB......",
            "...BBBBB.......",
            "....K.K........",
            "....K.K........",
        ]
    }

    // MARK: - Badges

    /// The corner. It says which kind of stop this is, and it is the one part
    /// of the drawing that does not move with the chick.
    ///
    /// Every badge keeps a clear column between itself and the body -- at rest,
    /// in every pose, and at every offset a face can reach, since the body
    /// moves under a badge that does not. On `done` and `waiting` the badge
    /// wears the body's own colour, so a single touching cell does not read as
    /// a badge beside a chick: it reads as one shape, and the tick grows out of
    /// its head. `scripts/mascot-images.sh` refuses to export art that does.
    enum Badge {
        static let none = [String](repeating: "...............", count: PixelChick.rows)

        static let ask = [
            "...........AAA.",
            ".............A.",
            "............A..",
            "............A..",
            "...............",
            "............A..",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
        ]

        static let bang = [
            "............A..",
            "............A..",
            "............A..",
            "............A..",
            "...............",
            "............A..",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
        ]

        /// Drawn clear of the body rather than reaching back across it: the
        /// short arm used to sit one column off the chick's cheek, in the same
        /// green, and the two fused into a stick growing out of its head.
        static let tick = [
            "...............",
            "..............A",
            "...........A.A.",
            "............A..",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
        ]

        /// A column further out than the others need to be, because `error` is
        /// the one face that shifts sideways and would otherwise shiver into
        /// its own badge.
        static let cross = [
            "............A.A",
            ".............A.",
            "............A.A",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
        ]

        static let bar = [
            "...............",
            "...........AAA.",
            "...........AAA.",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
        ]

        static let zed = [
            "...........AAA.",
            "............A..",
            "...........AAA.",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
        ]

        /// The same z one row down, so it has somewhere to drift up from.
        static let zedLow = [
            "...............",
            "...........AAA.",
            "............A..",
            "...........AAA.",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
            "...............",
        ]
    }

    // MARK: - Frames

    /// A pose with a badge laid over it. The badge wins wherever it has ink,
    /// which is what lets the tick reach across the body's last column.
    static func frame(_ pose: [String], _ badge: [String] = Badge.none) -> [String] {
        zip(pose, badge).map { pose, badge in
            String(zip(pose, badge).map { $0.1 == "." ? $0.0 : $0.1 })
        }
    }

    /// The resting frame: the face standing still, which is what the readme's
    /// table and every still export show.
    static func grid(_ face: MascotFace) -> [String] {
        clip(face).loop[0].grid
    }

    // MARK: - Performances

    /// How one face moves.
    ///
    /// Every face has a pulse of its own, because a state is not only a colour:
    /// running hops, waiting bobs and cheeps at you, stalled sweats and sags,
    /// done breathes, error shivers, idle sleeps, spent does not move at all.
    /// Reading the island should not require reading anything.
    ///
    /// The first beat of every loop is the face at rest, so a sprite with
    /// motion switched off -- or a Mac asking for less of it -- shows exactly
    /// the drawing this app has always shown.
    static func clip(_ face: MascotFace) -> PixelClip {
        switch face {
        case .running:
            // A hop, a long pause, and a double blink in it. The pause is what
            // keeps a room full of these from looking like a fairground: work
            // in progress is the least of your worries.
            return PixelClip(loop: [
                beat(Pose.stand, for: 0.34),
                beat(Pose.crouch, for: 0.08),
                beat(Pose.airborne, for: 0.18, dy: 1),
                beat(Pose.dangle, for: 0.08, dy: 1),
                beat(Pose.crouch, for: 0.08),
                beat(Pose.stand, for: 1.02),
                beat(Pose.shut, for: 0.09),
                beat(Pose.stand, for: 0.13),
                beat(Pose.shut, for: 0.09),
                beat(Pose.stand, for: 0.51),
            ], arrival: [
                beat(Pose.crouch, for: 0.07),
                beat(Pose.airborne, for: 0.15, dy: 1),
                beat(Pose.crouch, for: 0.07),
                beat(Pose.stand, for: 0.08),
            ])

        case .waiting:
            // The state the app exists for, so this is the one performance
            // allowed to be insistent: two bobs, a cheep at the top of each,
            // and the badge blinking on its own beat behind it. The frequency
            // is fixed -- escalation rides on the island's width instead,
            // which is what peripheral vision actually picks up.
            return PixelClip(loop: [
                beat(Pose.wide, Badge.ask, for: 0.26),
                beat(Pose.wide, Badge.ask, for: 0.16, dy: 1),
                beat(Pose.widePeep, Badge.ask, for: 0.14, dy: 1),
                beat(Pose.wide, Badge.ask, for: 0.14),
                beat(Pose.wide, Badge.none, for: 0.20),
                beat(Pose.wide, Badge.ask, for: 0.16, dy: 1),
                beat(Pose.widePeep, Badge.ask, for: 0.14, dy: 1),
                beat(Pose.wide, Badge.ask, for: 0.30),
                beat(Pose.wide, Badge.none, for: 0.24),
                beat(Pose.wide, Badge.ask, for: 0.46),
            ], arrival: [
                beat(Pose.wide, Badge.ask, for: 0.10, dy: 1),
                beat(Pose.widePeep, Badge.ask, for: 0.16, dy: 1),
                beat(Pose.wide, Badge.ask, for: 0.10),
                beat(Pose.wide, Badge.ask, for: 0.10, dy: 1),
                beat(Pose.wide, Badge.ask, for: 0.10),
            ])

        case .stalled:
            // Waiting on a tool rather than on you, so it is tired rather than
            // urgent: the drop falls, the chick sags a cell, the badge keeps
            // its own slower blink.
            return PixelClip(loop: [
                beat(Pose.dripHigh, Badge.bang, for: 0.62),
                beat(Pose.dripMid, Badge.bang, for: 0.10),
                beat(Pose.dripLow, Badge.bang, for: 0.10),
                beat(Pose.dry, Badge.none, for: 0.38),
                beat(Pose.dry, Badge.bang, for: 0.40, dy: -1),
                beat(Pose.dry, Badge.bang, for: 0.30),
                beat(Pose.dry, Badge.none, for: 0.40),
                beat(Pose.dripHigh, Badge.bang, for: 0.70),
            ], arrival: [
                beat(Pose.dry, Badge.bang, for: 0.14),
                beat(Pose.dry, Badge.bang, for: 0.26, dy: -1),
                beat(Pose.dripHigh, Badge.bang, for: 0.18),
            ])

        case .done:
            // Nothing is burning, so it breathes: one cell, twice as slowly as
            // anything else moves, with a blink and a small cheep in it.
            return PixelClip(loop: [
                beat(Pose.happy, Badge.tick, for: 1.20),
                beat(Pose.happy, Badge.tick, for: 0.50, dy: 1),
                beat(Pose.happy, Badge.tick, for: 0.90),
                beat(Pose.shut, Badge.tick, for: 0.10),
                beat(Pose.happy, Badge.tick, for: 0.30),
                beat(Pose.happyPeep, Badge.tick, for: 0.20),
                beat(Pose.happy, Badge.tick, for: 0.40),
            ], arrival: [
                beat(Pose.crouch, Badge.tick, for: 0.07),
                beat(Pose.airborne, Badge.tick, for: 0.16, dy: 1),
                beat(Pose.dangle, Badge.tick, for: 0.10, dy: 1),
                beat(Pose.crouch, Badge.tick, for: 0.08),
                beat(Pose.happy, Badge.tick, for: 0.10),
            ])

        case .error:
            // A shiver, then stillness. Sideways rather than up, because a
            // failure is not a state anything is bouncing about.
            return PixelClip(loop: [
                beat(Pose.crossed, Badge.cross, for: 0.06),
                beat(Pose.crossed, Badge.cross, for: 0.06, dx: 1),
                beat(Pose.crossed, Badge.cross, for: 0.06),
                beat(Pose.crossed, Badge.cross, for: 0.06, dx: 1),
                beat(Pose.crossed, Badge.cross, for: 0.06),
                beat(Pose.crossed, Badge.cross, for: 0.06, dx: 1),
                beat(Pose.crossed, Badge.cross, for: 2.84),
            ], arrival: [
                beat(Pose.crossed, Badge.cross, for: 0.05, dx: 1),
                beat(Pose.crossed, Badge.cross, for: 0.05),
                beat(Pose.crossed, Badge.cross, for: 0.05, dx: 1),
                beat(Pose.crossed, Badge.cross, for: 0.05),
                beat(Pose.crossed, Badge.cross, for: 0.05, dx: 1),
                beat(Pose.crossed, Badge.cross, for: 0.10),
            ])

        case .idle:
            // Asleep: a slow breath, and a z that drifts up off the corner and
            // is gone before the next one starts.
            return PixelClip(loop: [
                beat(Pose.shut, Badge.zed, for: 0.90),
                beat(Pose.shut, Badge.zedLow, for: 0.70, dy: -1),
                beat(Pose.shut, Badge.zed, for: 0.90),
                beat(Pose.shut, Badge.none, for: 0.70),
                beat(Pose.shut, Badge.zedLow, for: 0.90, dy: -1),
                beat(Pose.shut, Badge.zed, for: 0.90),
            ], arrival: [
                beat(Pose.stand, Badge.zed, for: 0.16),
                beat(Pose.shut, Badge.zed, for: 0.14),
            ])

        case .spent:
            // Awake and walled in. The body does not move -- there is nothing
            // it could do -- and only the bar pulses, because the one thing
            // still happening is a clock.
            return PixelClip(loop: [
                beat(Pose.stand, Badge.bar, for: 0.90),
                beat(Pose.stand, Badge.none, for: 0.30),
                beat(Pose.stand, Badge.bar, for: 0.60),
                beat(Pose.shut, Badge.bar, for: 0.10),
                beat(Pose.stand, Badge.bar, for: 0.50),
            ], arrival: [
                beat(Pose.stand, Badge.bar, for: 0.20, dy: -1),
                beat(Pose.stand, Badge.bar, for: 0.16),
            ])
        }
    }

    private static func beat(_ pose: [String], _ badge: [String] = Badge.none,
                             for seconds: Double, dx: Int = 0, dy: Int = 0) -> PixelBeat {
        PixelBeat(grid: frame(pose, badge), seconds: seconds, dx: dx, dy: dy)
    }

    /// How far to nudge the canvas so the body, rather than the whole grid,
    /// sits in the middle of whatever slot it is given.
    static func bodyCentringOffset(cell: CGFloat) -> CGFloat {
        CGFloat(columns - bodyColumns) / 2 * cell
    }

    /// Cells of one kind, as a path of square pixels. Kept for the still
    /// exporter, which draws a resting face and never an animated one.
    static func path(_ token: Character, face: MascotFace,
                     cell: CGFloat, origin: CGPoint = .zero) -> CGPath {
        PixelGrid.path(token, grid: grid(face), cell: cell, rows: rows, origin: origin)
    }
}

extension MascotFace {
    /// The state's colour. Worn by the body, the badge, and any text that is
    /// talking about the same session, so one hue answers "what is going on"
    /// before any glyph has to be read.
    var colour: NSColor {
        switch self {
        // Cool and receding: work in progress is the least of your worries.
        case .running: Brand.cyan
        // Warm and advancing. Brand orange is spent here and nowhere else,
        // because this is the one state the app exists for.
        case .waiting: Brand.orange
        case .stalled, .error: Brand.red
        case .done: Brand.green
        // Grey because nothing is running on it, not because nothing is wrong.
        // The badge is what says which of those it is.
        case .idle, .spent: Brand.idleBody
        }
    }

    var bodyColour: NSColor { colour }

    /// Beak and feet stay brand orange whatever the body is doing: hue is the
    /// state, but the silhouette and that orange beak are the identity.
    var beakColour: NSColor { self == .idle ? Brand.idleBeak : Brand.beak }

    var badgeColour: NSColor {
        switch self {
        case .running: .clear
        // A shade lighter than the grey body, so the z still reads.
        case .idle: Brand.idleBadge
        case .waiting, .stalled, .done, .error: colour
        // The one face whose badge is not its body's colour: the body is grey
        // because nothing is moving, and the badge is what makes that urgent.
        case .spent: Brand.red
        }
    }

    /// The layers the art is drawn in, back to front.
    var inks: [PixelInk] {
        [PixelInk(token: "B", colour: bodyColour),
         PixelInk(token: "K", colour: beakColour),
         PixelInk(token: "E", colour: Brand.eye),
         PixelInk(token: "S", colour: Brand.cyan),
         PixelInk(token: "A", colour: badgeColour, moves: false)]
    }
}

extension SessionState {
    /// How one session wears the mark.
    var face: MascotFace {
        switch self {
        case .running: .running
        case .done: .done
        // A prompt only a person can answer is a different kind of stop from a
        // tool that will not finish, and the badge is where that difference shows.
        case .blocked(let reason): reason.isImmediate ? .waiting : .stalled
        }
    }
}
