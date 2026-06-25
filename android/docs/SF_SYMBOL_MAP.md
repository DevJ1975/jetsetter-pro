# SF Symbol → Material Icons Map (Android)

The iOS app uses **only SF Symbols** (`Image(systemName:)`) — there are **no
custom icon assets**. This document maps every SF Symbol referenced in the iOS
source to its closest **Material Symbols / Material Icons** name and the matching
**Compose `Icons.*`** reference.

The list below was produced by grepping `systemName:` across
`JetSetter Pro/` (≈91 distinct symbols). Where an exact Material equivalent does
not exist, the closest visual match is given plus a note; for the handful with no
good analog, ship a **custom vector** in `res/drawable/` (24×24 `VectorDrawable`)
and load it with `ImageVector.vectorResource(R.drawable.ic_…)`.

---

## Setup — `material-icons-extended`

Stock Compose ships only a small core set (`androidx.compose.material:material-icons-core`,
~40 icons via `Icons.Default.*`). Almost everything in the table needs the
**extended** set:

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("androidx.compose.material:material-icons-extended")
}
```

Reference icons as:

```kotlin
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.automirrored.filled.ArrowForward // direction-aware

Icon(Icons.Filled.Flight, contentDescription = "Flight")
Icon(Icons.Outlined.Info, contentDescription = "Info")
Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null) // flips in RTL
```

Notes:
- **`material-icons-extended` is large** (thousands of icons) and is being
  deprecated in favor of downloading individual Material Symbols. For a leaner
  release, replace the dependency with hand-picked `res/drawable` Material Symbols
  exports later; the names in the "Material Symbol" column are the exact symbol
  names to download from fonts.google.com/icons.
- **`AutoMirrored`** variants exist for directional glyphs (arrows, chevrons,
  list, send). Use them so icons flip correctly in RTL locales — SF Symbols do
  this automatically; Compose does not unless you opt in.
- **Fill vs. outline:** SF `*.fill` → Material `Icons.Filled.*`; non-fill SF →
  `Icons.Outlined.*` (fall back to `Filled` when no outlined variant exists).
- **Compose name ≠ Material Symbol name.** Compose PascalCase-izes and sometimes
  abbreviates (e.g. symbol `flight_takeoff` → `Icons.Filled.FlightTakeoff`;
  symbol `directions_car` → `Icons.Filled.DirectionsCar`). Both columns are given.

---

## Navigation & chrome

| SF Symbol | Material Symbol | Compose `Icons.*` | Notes |
|---|---|---|---|
| `chevron.right` | `chevron_right` | `Icons.AutoMirrored.Filled.KeyboardArrowRight` | Use AutoMirrored for RTL |
| `chevron.up.chevron.down` | `unfold_more` | `Icons.Filled.UnfoldMore` | Expand/collapse affordance |
| `arrow.right` | `arrow_forward` | `Icons.AutoMirrored.Filled.ArrowForward` | |
| `arrow.right.circle.fill` | `arrow_circle_right` | `Icons.Filled.ArrowCircleRight` | |
| `arrow.up.right` | `north_east` | `Icons.Filled.NorthEast` | Diagonal / "open external" |
| `arrow.up.circle.fill` | `arrow_circle_up` | `Icons.Filled.ArrowCircleUp` | |
| `arrow.down.circle.fill` | `arrow_circle_down` | `Icons.Filled.ArrowCircleDown` | |
| `arrow.left.arrow.right` | `swap_horiz` | `Icons.Filled.SwapHoriz` | Swap origin/destination |
| `arrow.clockwise` | `refresh` | `Icons.Filled.Refresh` | |
| `arrow.clockwise.circle.fill` | `refresh` (in circle) | `Icons.Filled.Refresh` | No filled-circle variant; wrap in tinted circle |
| `arrow.triangle.2.circlepath` | `sync` | `Icons.Filled.Sync` | "Reroute"/refresh loop |
| `plus` | `add` | `Icons.Filled.Add` | |
| `plus.circle.fill` | `add_circle` | `Icons.Filled.AddCircle` | Primary "add" CTA |
| `xmark` | `close` | `Icons.Filled.Close` | Dismiss |
| `xmark.circle.fill` | `cancel` | `Icons.Filled.Cancel` | Clear field / remove |
| `magnifyingglass` | `search` | `Icons.Filled.Search` | |
| `pencil.circle.fill` | `edit` (in circle) | `Icons.Filled.Edit` | No filled-circle; wrap, or `Icons.Filled.ModeEdit` |
| `gearshape.fill` | `settings` | `Icons.Filled.Settings` | |
| `slider.horizontal.3` | `tune` | `Icons.Filled.Tune` | Filters |
| `ellipsis.circle` | `more_horiz` | `Icons.Filled.MoreHoriz` | "More" menu |
| `rectangle.grid.3x2.fill` | `grid_view` | `Icons.Filled.GridView` | Dashboard / grid |
| `square.and.arrow.up` | `ios_share` / `share` | `Icons.Filled.Share` | Share sheet |
| `link.circle` | `link` | `Icons.Filled.Link` | |
| `link.circle.fill` | `link` | `Icons.Filled.Link` | Filled-circle: wrap in tinted circle |
| `circle.fill` | `circle` | `Icons.Filled.Circle` | Status dot / bullet |
| `questionmark.circle` | `help` | `Icons.AutoMirrored.Outlined.HelpOutline` | |

## Travel & transport

| SF Symbol | Material Symbol | Compose `Icons.*` | Notes |
|---|---|---|---|
| `airplane` | `flight` | `Icons.Filled.Flight` | |
| `airplane.circle` | `flight` (in circle) | `Icons.Outlined.Flight` | No circle variant; wrap |
| `airplane.circle.fill` | `flight` (in circle) | `Icons.Filled.Flight` | Wrap in tinted circle for parity |
| `airplane.departure` | `flight_takeoff` | `Icons.Filled.FlightTakeoff` | |
| `airplane.arrival` | `flight_land` | `Icons.Filled.FlightLand` | (used by BagStatus) |
| `paperplane.fill` | `send` | `Icons.AutoMirrored.Filled.Send` | Send message (IRIS chat) |
| `suitcase.fill` | `luggage` | `Icons.Filled.Luggage` | |
| `briefcase.fill` | `work` / `business_center` | `Icons.Filled.BusinessCenter` | Business / work travel |
| `building.fill` | `apartment` | `Icons.Filled.Apartment` | Hotel / building |
| `building.2.fill` | `domain` / `business` | `Icons.Filled.Business` | Hotel reservation |
| `bed.double.fill` | `king_bed` / `hotel` | `Icons.Filled.Hotel` | Hotel itinerary item |
| `car.fill` | `directions_car` | `Icons.Filled.DirectionsCar` | |
| `car.2.fill` | `directions_car` (x2) | `Icons.Filled.DirectionsCar` | No "2-car"; reuse or custom |
| `steeringwheel` | `airline_seat_recline_normal` / — | `Icons.Filled.NoCrash` (loose) | **No exact match — ship custom `ic_steeringwheel`** |
| `road.lanes` | `add_road` / `route` | `Icons.Filled.Route` | Mileage (ExpenseCategory) |
| `fork.knife` | `restaurant` | `Icons.Filled.Restaurant` | Restaurant / dining |
| `ticket.fill` | `confirmation_number` | `Icons.Filled.ConfirmationNumber` | Event ticket |
| `globe` | `public` / `language` | `Icons.Filled.Public` | |
| `mappin` | `place` | `Icons.Filled.Place` | |
| `mappin.circle.fill` | `where_to_vote` / `place` | `Icons.Filled.Place` | Filled-circle: wrap |
| `mappin.and.ellipse` | `my_location` / `place` | `Icons.Filled.Place` | |
| `map.fill` | `map` | `Icons.Filled.Map` | |
| `location.fill` | `location_on` | `Icons.Filled.LocationOn` | |
| `location.circle.fill` | `my_location` | `Icons.Filled.MyLocation` | |
| `location.slash.fill` | `location_off` | `Icons.Filled.LocationOff` | Location disabled |

## Status, alerts & security

| SF Symbol | Material Symbol | Compose `Icons.*` | Notes |
|---|---|---|---|
| `checkmark` | `check` | `Icons.Filled.Check` | |
| `checkmark.circle.fill` | `check_circle` | `Icons.Filled.CheckCircle` | Success / packed |
| `checkmark.seal.fill` | `verified` | `Icons.Filled.Verified` | Verified / delivered |
| `checkmark.shield.fill` | `verified_user` | `Icons.Filled.VerifiedUser` | Secure / verified |
| `exclamationmark.triangle.fill` | `warning` | `Icons.Filled.Warning` | Warning / disruption |
| `exclamationmark.circle.fill` | `error` | `Icons.Filled.Error` | Error |
| `exclamationmark.shield.fill` | `gpp_maybe` / `security` | `Icons.Filled.GppMaybe` | Security warning |
| `info.circle` | `info` | `Icons.Outlined.Info` | |
| `questionmark.circle.fill` | `help` | `Icons.AutoMirrored.Filled.Help` | Unknown status |
| `bell` | `notifications` | `Icons.Outlined.Notifications` | |
| `bell.fill` | `notifications` | `Icons.Filled.Notifications` | |
| `bell.badge.fill` | `notifications_active` | `Icons.Filled.NotificationsActive` | Active alerts |
| `bell.slash.fill` | `notifications_off` | `Icons.Filled.NotificationsOff` | Muted |
| `shield` | `shield` / `security` | `Icons.Outlined.Shield` | |
| `shield.fill` | `shield` / `security` | `Icons.Filled.Security` | Insurance / protection |
| `lock.fill` | `lock` | `Icons.Filled.Lock` | |
| `lock.shield.fill` | `gpp_good` / `security` | `Icons.Filled.GppGood` | Encrypted vault |
| `faceid` | `face` / `face_unlock` | `Icons.Filled.Face` | Biometric (≈ Face ID) |
| `clock.fill` | `schedule` / `access_time_filled` | `Icons.Filled.AccessTimeFilled` | |
| `clock.badge.exclamationmark.fill` | `running_with_errors` / `schedule` | `Icons.Filled.RunningWithErrors` | Delay warning |
| `dot.radiowaves.left.and.right` | `sensors` / `wifi_tethering` | `Icons.Filled.Sensors` | Live tracking signal |
| `sos` | `sos` | `Icons.Filled.Sos` | Emergency |

## Finance & expenses

| SF Symbol | Material Symbol | Compose `Icons.*` | Notes |
|---|---|---|---|
| `dollarsign.circle` | `monetization_on` / `paid` | `Icons.Outlined.MonetizationOn` | |
| `dollarsign.circle.fill` | `monetization_on` / `paid` | `Icons.Filled.MonetizationOn` | |
| `wallet.pass` | `account_balance_wallet` | `Icons.Outlined.AccountBalanceWallet` | Travel Wallet |
| `wallet.pass.fill` | `account_balance_wallet` | `Icons.Filled.AccountBalanceWallet` | |
| `creditcard.fill` | `credit_card` | `Icons.Filled.CreditCard` | Payment / boarding pass |
| `receipt` | `receipt` / `receipt_long` | `Icons.Filled.ReceiptLong` | Expense receipt |
| `star.circle.fill` | `stars` | `Icons.Filled.Stars` | Loyalty / rewards |
| `star.fill` | `star` | `Icons.Filled.Star` | Rating / activity |
| `crown.fill` | `workspace_premium` / `military_tech` | `Icons.Filled.WorkspacePremium` | Premium / elite tier (no "crown" — closest) |

## Documents & files

| SF Symbol | Material Symbol | Compose `Icons.*` | Notes |
|---|---|---|---|
| `doc.text.fill` | `description` / `article` | `Icons.Filled.Description` | Document |
| `doc.on.doc` | `content_copy` / `file_copy` | `Icons.Filled.ContentCopy` | Copy / duplicate |
| `doc.badge.gearshape.fill` | `request_quote` / `description` | `Icons.Filled.Description` | Visa doc (compose closest) |
| `person.text.rectangle.fill` | `badge` / `contact_page` | `Icons.Filled.Badge` | Passport / ID card |
| `list.bullet.clipboard` | `assignment` / `checklist` | `Icons.AutoMirrored.Filled.Assignment` | Itinerary list |
| `list.bullet.rectangle.fill` | `view_list` / `list_alt` | `Icons.AutoMirrored.Filled.ListAlt` | |
| `list.number` | `format_list_numbered` | `Icons.AutoMirrored.Filled.FormatListNumbered` | |
| `checklist` | `checklist` / `fact_check` | `Icons.Filled.Checklist` | Packing list |
| `cross.case.fill` | `medical_services` / `vaccines` | `Icons.Filled.Vaccines` | Vaccination record |
| `cross.fill` | `local_hospital` / `add` | `Icons.Filled.LocalHospital` | Medical (ExpenseCategory) |
| `tray` | `inbox` | `Icons.Filled.Inbox` | |
| `tray.fill` | `inbox` | `Icons.Filled.Inbox` | |
| `tray.full.fill` | `inventory_2` / `move_to_inbox` | `Icons.Filled.MoveToInbox` | Bag "on belt" |
| `trash` | `delete` | `Icons.Filled.Delete` | |
| `arrow.up.bin.fill` | `upload_file` / `archive` | `Icons.Filled.Archive` | Bag "loading" (loader transfer) |

## People & contact

| SF Symbol | Material Symbol | Compose `Icons.*` | Notes |
|---|---|---|---|
| `person.fill` | `person` | `Icons.Filled.Person` | |
| `person.crop.circle` | `account_circle` | `Icons.Outlined.AccountCircle` | Profile |
| `person.crop.circle.fill` | `account_circle` | `Icons.Filled.AccountCircle` | |
| `phone.fill` | `call` / `phone` | `Icons.Filled.Call` | Emergency contact |
| `envelope.fill` | `mail` / `email` | `Icons.Filled.Email` | |
| `calendar` | `calendar_today` / `event` | `Icons.Filled.CalendarToday` | |
| `calendar.badge.checkmark` | `event_available` | `Icons.Filled.EventAvailable` | Calendar synced |
| `calendar.badge.plus` | `event` / `add` | `Icons.Filled.EditCalendar` | Add to calendar |

## Imaging, AI & misc

| SF Symbol | Material Symbol | Compose `Icons.*` | Notes |
|---|---|---|---|
| `camera.on.rectangle` | `add_a_photo` / `photo_camera` | `Icons.Filled.AddAPhoto` | Scan receipt / capture |
| `sparkles` | `auto_awesome` | `Icons.Filled.AutoAwesome` | AI / IRIS magic |
| `wand.and.stars` | `auto_fix_high` | `Icons.Filled.AutoFixHigh` | AI generate |
| `brain.head.profile` | `psychology` | `Icons.Filled.Psychology` | Intelligence feature |
| `sun.max.fill` | `light_mode` / `wb_sunny` | `Icons.Filled.LightMode` | Light theme / weather |
| `moon.fill` | `dark_mode` / `bedtime` | `Icons.Filled.DarkMode` | Dark theme |
| `circle.lefthalf.filled` | `brightness_medium` / `contrast` | `Icons.Filled.BrightnessMedium` | System theme toggle |
| `cloud.fill` | `cloud` | `Icons.Filled.Cloud` | Weather |
| `fuelpump.fill` | `local_gas_station` | `Icons.Filled.LocalGasStation` | Fuel / carbon |
| `leaf.fill` | `eco` / `energy_savings_leaf` | `Icons.Filled.Eco` | Carbon / sustainability |
| `figure.walk` | `directions_walk` | `Icons.AutoMirrored.Filled.DirectionsWalk` | Walking directions |

---

## Symbols with no exact Material equivalent

Ship these as **custom 24×24 `VectorDrawable`s** in `res/drawable/` (then
`ImageVector.vectorResource(...)`). The "closest" listed above is acceptable as an
interim until the custom asset lands.

| SF Symbol | Why | Recommendation |
|---|---|---|
| `steeringwheel` | No steering-wheel glyph in Material | Custom `ic_steeringwheel.xml` (driver / self-drive rental) |
| `crown.fill` | Material has no crown | Custom `ic_crown.xml`, or accept `WorkspacePremium` for elite tier |
| `airplane.circle.fill` / `airplane.circle` | Material `flight` has no circular framed variant | Wrap `Icons.Filled.Flight` in a tinted `CircleShape` background, or custom |
| `mappin.circle.fill` | No "pin-in-circle" | Wrap `Icons.Filled.Place` in a circle, or custom |
| `arrow.clockwise.circle.fill` / `pencil.circle.fill` / `link.circle.fill` | Material lacks the filled-circle framed forms | Wrap the base icon (`Refresh` / `ModeEdit` / `Link`) in a tinted circle composable |
| `doc.badge.gearshape.fill` | Compound doc+gear (visa) glyph absent | Custom `ic_visa_doc.xml`, or `Description` interim |
| `dot.radiowaves.left.and.right` | "Live signal" semantics | `Icons.Filled.Sensors` is close; custom for exact look |

**Helper for "framed-in-circle" symbols** (covers the many `*.circle.fill`
cases) so you do not need a custom asset per symbol:

```kotlin
@Composable
fun CircleIcon(
    icon: ImageVector,
    tint: Color,
    background: Color = tint.copy(alpha = 0.15f),
    size: Dp = 28.dp,
) {
    Box(
        Modifier.size(size).clip(CircleShape).background(background),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(size * 0.62f))
    }
}
```
