# 🎨 Rewards Catalog - Design Reference Card

## Quick Reference for Developers

### Color Palette

```
Primary Orange:          #F97316
Orange (10% opacity):    rgba(249, 115, 22, 0.1)
Orange (15% opacity):    rgba(249, 115, 22, 0.15)
Orange (8% opacity):     rgba(249, 115, 22, 0.08)
Orange (20% opacity):    rgba(249, 115, 22, 0.2)

Light Theme BG:          #FAF9F7
Light Theme Card:        #FFFFFF
Light Theme Image BG:    #F5F5F5
Light Theme Border:      #E0E0E0 (gray[300])
Light Theme Muted:       Colors.grey[600]

Dark Theme BG:           #121212
Dark Theme Card:         #1E1E1E
Dark Theme Image BG:     #2A2A2A
Dark Theme Border:       #424242 (gray[700])
Dark Theme Muted:        Colors.grey[500]

Status Green:            Colors.green
Status Amber:            Colors.amber
Status Red:              Colors.red
```

---

### Typography Sizes

```
App Bar Title:           14px, 600 weight, letter-spaced 0.5
Section Header:          16px, 600 weight
Product Name:            15px, 700 weight, letter-spaced 0.2
Product Price:           16px, 700 weight
Badge Text:              12px, 600 weight, letter-spaced 0.3
Filter Chip:             13px, 500-600 weight
Button Label:            14px, 600 weight, letter-spaced 0.5
Body Text:               14px, 400 weight
Small Text:              12px, 400 weight
```

---

### Spacing & Sizing

```
Page Horizontal Margin:      16px
Page Vertical Top:           16px
Page Vertical Bottom:        12px
Card Padding:                14px (all sides)
Section Gap:                 14px
Component Gap:               8px (chips, etc.)
Image Section Height:        140px
Button Height:               44px
AppBar Height:               56px
Border Radius (Major):       16px
Border Radius (Chips):       20px
Border Radius (Minor):       12px
Border Width:                1px (normal), 1.5px (focus)
```

---

### Elevation & Shadows

```
Card Base:
  - Elevation: 2
  - Shadow Color: orange.withOpacity(0.1)
  - Blur Radius: 8
  - Offset: Offset(0, 2)

Card Hover:
  - Elevation: 8
  - Shadow Color: orange.withOpacity(0.3)
  - Blur Radius: 12
  - Offset: Offset(0, 4)

Button:
  - Normal: 2px elevation
  - Disabled: 0px elevation
  - Hover: Implicit through Material

Chip (Selected):
  - Shadow Color: orange.withOpacity(0.3)
  - Blur Radius: 8
  - Offset: Offset(0, 2)
```

---

### Animation Timings

```
Filter Chip Animation:
  - Duration: 200ms
  - Curve: Curves.easeInOut
  - Properties: Background, text color, shadow

Card Hover Animation:
  - Duration: 200ms
  - Curve: Curves.easeOut
  - Property: Scale (1.0 → 1.01)

Clear Icon Animation:
  - Duration: Implicit (TextField)
  - Behavior: Smooth fade in/out

Button Press:
  - Duration: Material default (200ms)
  - Curve: Material default
```

---

### Component Structure

```
RewardsCatalogScreen
├── _buildModernAppBar()
│   └── PreferredSize(56px) + AppBar
├── RewardsTopSwitcher
├── Search Bar Group
│   ├── _buildModernSearchBar()
│   └── _buildFilterChips()
└── Products ListView
    ├── ProductCard (Modern)
    ├── Loading State
    ├── Empty State
    └── Error State
```

---

### Responsive Breakpoints

```
Mobile (< 600px):
  - Full-width cards
  - Single column layout
  - Horizontal scroll for chips

Tablet (600px - 900px):
  - Full-width cards
  - Single column layout
  - Horizontal scroll for chips

Desktop (> 900px):
  - Could use 2-column grid (future enhancement)
  - More chips visible without scroll
```

---

### Dark/Light Theme Detection

```dart
final isDark = Theme.of(context).brightness == Brightness.dark;

// Use for:
final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
final textColor = isDark ? Colors.grey[300] : Colors.grey[700];
```

---

### Key Component Features

#### Filter Chip
- Pill-shaped (20px borderRadius)
- Selected: Filled with orange, white text, shadow
- Unselected: Outline, gray text
- Emojis for visual clarity: 💰 ⭐
- 200ms smooth animation

#### Product Card
- Full-width, 16px border radius
- 140px image section with soft border
- Status badge (top right corner)
- Separate rating badge (amber)
- Points badge (orange tint background)
- 44px action button
- 1.01x scale on hover

#### Search Bar
- Full-width, pill-shaped (14px)
- Dynamic clear icon
- Orange focus border
- Soft background (theme-aware)

---

### States

#### Loading
```dart
CircularProgressIndicator(
  valueColor: const AlwaysStoppedAnimation(_primaryOrange),
)
```

#### Empty
```
🎁 Icon (48px, in circle)
"No rewards found"
"Try adjusting your search criteria"
```

#### Error
```
❌ Icon (48px, in red circle)
"Something went wrong"
Error message
[Try Again] button
```

---

### Disabled State (Button)

```
Background:    Colors.grey[300]
Text Color:    Colors.grey[600]
Loading Icon:  Colors.grey[600] (spinner)
Elevation:     0
Cursor:        not-allowed
```

---

### Status Badges

```
Available:
  - Background: Colors.green.withOpacity(0.15)
  - Text: Colors.green[700]
  - Padding: 8h x 4v

Limited:
  - Background: Colors.amber.withOpacity(0.15)
  - Text: Colors.amber[700]
  - Padding: 8h x 4v
```

---

### Badge Styles

#### Rating Badge
```
Background:    Colors.amber.withOpacity(0.15)
Text Color:    Colors.amber[700]
Icon Color:    Colors.amber[600]
Padding:       8h x 4v
Border Radius: 8px
```

#### Points Badge
```
Background:    _primaryOrange.withOpacity(0.08)
Border:        _primaryOrange.withOpacity(0.2)
Text Color:    _primaryOrange
Icon BG:       _primaryOrange.withOpacity(0.15)
Padding:       11px all
Border Radius: 12px
```

---

### Icons Used

```
🔍 Icons.search              (Search)
✕ Icons.clear                (Clear search)
🎁 Icons.card_giftcard       (Gift/Points)
⭐ Icons.star                (Rating)
🛍️ Icons.shopping_bag_outlined (Empty state)
❌ Icons.error_outline        (Error state)
🛒 Icons.shopping_cart        (Request button)
🔄 Icons.refresh              (Retry button)
```

---

### Usage Examples

#### Building Modern Chip
```dart
_ModernFilterChip(
  label: '💰 Low to High',
  isSelected: _sortBy == 'price_asc',
  isDark: isDark,
  onSelected: () => setState(() => _sortBy = 'price_asc'),
)
```

#### Using Product Card
```dart
ProductCard(
  product: product,
  onRequestPressed: () {
    context.push('/rewards/product/${product.productId}');
  },
)
```

#### Theme-Aware Colors
```dart
final isDark = Theme.of(context).brightness == Brightness.dark;
final scaffoldBg = isDark ? const Color(0xFF121212) : const Color(0xFFFAF9F7);
final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
```

---

### Performance Checklist

- [ ] AnimationController properly disposed
- [ ] Theme.of() called once and cached
- [ ] No unnecessary rebuilds
- [ ] ListView uses proper builders
- [ ] Images optimized
- [ ] Fonts cached appropriately

---

### Accessibility Checklist

- [ ] Touch targets ≥ 44px
- [ ] Font size ≥ 12px
- [ ] Contrast ratio ≥ 4.5:1
- [ ] Focus states visible
- [ ] Semantic structure
- [ ] No color-only indicators

---

### Testing Checklist

- [ ] Light theme renders correctly
- [ ] Dark theme renders correctly
- [ ] Animations smooth (60fps)
- [ ] Responsive on small/large screens
- [ ] Touch interactions work
- [ ] Hover effects work (if applicable)
- [ ] All states display correctly
- [ ] Navigation works
- [ ] No console errors

---

### Common Modifications

#### Change Primary Color
```dart
// Replace all instances of:
const Color _primaryOrange = Color(0xFFF97316);
// With new color:
const Color _primaryOrange = Color(0xXXXXXXXX);
```

#### Adjust Card Height
```dart
// In image section:
height: 140, // Change this value
```

#### Modify Animation Speed
```dart
// In AnimationController:
duration: const Duration(milliseconds: 200), // Change this
```

#### Change Button Height
```dart
// In action button:
height: 44, // Change to desired height
```

---

### Troubleshooting

**Cards look cramped:**
- Increase `_buildImageSection` height
- Increase section gaps (change 14 to 16)

**Animations lag:**
- Check performance in Profile mode
- Reduce animation duration
- Check for heavy rebuilds

**Colors wrong in dark mode:**
- Verify isDark variable is being used
- Check Theme colors in theme configuration

**Text not readable:**
- Increase font size
- Check contrast ratio
- Verify isDark theme colors

---

## 📱 Quick Start

1. Review **REWARDS_CATALOG_REDESIGN.md** for detailed specs
2. Check **REWARDS_CATALOG_DESIGN_SHOWCASE.md** for visuals
3. Use this card as a quick reference
4. Refer to inline code comments for details

---

## 🎯 Key Takeaways

✅ **Modern Material 3 Design**
✅ **Smooth Animations (200ms)**
✅ **Full Theme Support (Light/Dark)**
✅ **Accessibility First**
✅ **Premium Visual Feel**
✅ **100% Backward Compatible**
✅ **Production Ready**

---

## 📞 Questions?

See the comprehensive documentation files for detailed answers!
