# Teacher Tests Screen - Visual Design Guide

## Component Anatomy

### Header Component
```
┌────────────────────────────────────────────────────┐
│ 🎨 GRADIENT BACKGROUND (Charcoal → Navy)          │
│                                                    │
│         TESTS                                      │
│    [CENTERED, 28px, W700]                          │
│                                                    │
│   Manage your assessments and monitor             │
│     student performance                           │
│         [12px, 70% opacity]                        │
└────────────────────────────────────────────────────┘
  Padding: 18px V, 20px H
```

### Search Bar
```
┌────────────────────────────────────────────────────┐
│  🔍  Search tests...                               │
└────────────────────────────────────────────────────┘
  24px Radius | Soft Shadow | Dark Background
  Padding: 12px H, 12px V inside
```

### Tab Navigation (Horizontal Scroll)
```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ 🟢 All Tests │  │  Live        │  │  Scheduled   │
└──────────────┘  └──────────────┘  └──────────────┘
  Selected:           Unselected:       Unselected:
  - Muted Green      - Outline Border   - Outline Border
  - Solid Fill       - Transparent      - Transparent
  - Soft Shadow      - No Shadow        - No Shadow
  
  Height: 40px | Padding: 16px H | Radius: 24px
```

---

## Test Card Layouts

### SCHEDULED CARD (Blue Theme)
```
┌────────────────────────────────────────────────┐
│                                                │
│  🔵 SCHEDULED          [📊]                    │
│                                                │
│  Final Exam                                    │
│  Class 10-A                                    │
│  ─────────────────────────────────────────     │
│  📅 Starts: 15/01/25, 10:00                   │
│                                                │
│  [Scheduled Button]                            │
│                                                │
└────────────────────────────────────────────────┘
  
  Radius: 20px | Shadow: Soft (4px, 12px blur)
  Padding: 18px all | Status: Blue #3B82F6
  
  Layout Height: ~160px
  Colors:
  - Badge BG: Blue with low opacity
  - Badge Text: Blue
  - Icon Container: Blue tinted
```

### LIVE CARD (Orange Theme)
```
┌────────────────────────────────────────────────┐
│                                                │
│  🟠 LIVE                [📊]                   │
│                                                │
│  Unit Test                                     │
│  Class 9-B                                     │
│  ─────────────────────────────────────────     │
│  ███████░░░░ 70%                              │
│  21 / 30 responses                             │
│                                                │
│  ┌─────────────────────────────────────────┐  │
│  │ ⏱️ 02:45:30              Live now       │  │
│  └─────────────────────────────────────────┘  │
│                                                │
└────────────────────────────────────────────────┘
  
  Radius: 20px | Shadow: Prominent
  Padding: 18px all | Status: Orange #F97316
  
  Progress Bar:
  - BG: Divider color (10% opacity)
  - Fill: Orange solid
  - Height: 6px | Radius: 999px (pill)
  
  Timer Container:
  - BG: Orange (10% opacity)
  - Border: Orange (25% opacity)
  - Radius: 12px
  - Height: ~44px
```

### COMPLETED CARD (Green Theme)
```
┌────────────────────────────────────────────────┐
│                                                │
│  🟢 COMPLETED           [📊]                   │
│                                                │
│  Quiz 5 - Science                              │
│  Class 8-C                                     │
│  ─────────────────────────────────────────     │
│  Completion Rate              [85%]            │
│                                                │
│  ████████░░ 85%                                │
│                                                │
│  Completed: 10/01/25                           │
│  28 of 33 students                             │
│  ─────────────────────────────────────────     │
│  ┌─────────────────────────────────────────┐  │
│  │      VIEW RESULTS                       │  │
│  └─────────────────────────────────────────┘  │
│                                                │
└────────────────────────────────────────────────┘
  
  Radius: 20px | Shadow: Prominent
  Padding: 18px all | Status: Green #10B981
  
  View Results Button:
  - BG: Green #10B981
  - Text: White (bold)
  - Radius: 14px
  - Shadow: Green (30% opacity)
  - Full width, centered
```

---

## Color Specifications

### Muted Green (#5B7C66)
```
RGB: 91, 124, 102
Used for:
  ✓ Selected tab background
  ✓ FAB background
  ✓ Selected state indicators
  
Shadows:
  - Dark mode: 35% opacity
  - Light mode: 25% opacity
```

### Orange (#F97316)
```
RGB: 249, 115, 22
Used for:
  ✓ Live status badges
  ✓ Progress bars (live tests)
  ✓ Timer elements
  ✓ Live status indicators
  
Shadows:
  - 30-35% opacity
```

### Blue (#3B82F6)
```
RGB: 59, 130, 246
Used for:
  ✓ Scheduled status badges
  ✓ Calendar/date icons
  ✓ Scheduled state indicators
  
Opacity variations:
  - Badge BG: 10%
  - Border: 20%
```

### Green (#10B981)
```
RGB: 16, 185, 129
Used for:
  ✓ Completion percentage badges
  ✓ View Results button
  ✓ Completed status indicators
  
Shadows:
  - 30% opacity
```

---

## Typography System

### Headers & Titles
- **Screen Title**: 28px, W700 (Tests)
- **Card Title**: 16px, W700 (Test name)
- **Subtitle**: 12px, W400 (Description text)

### Labels & Badges
- **Badge Text**: 10px, W700 (SCHEDULED, LIVE, COMPLETED)
- **Tab Label**: 13px, W600 (All Tests, Live, etc.)
- **Status Text**: 12px, W600 (completion text)

### Supporting Text
- **Metadata**: 12px, W500 (dates, counts)
- **Helper Text**: 11px, W400 (secondary info)
- **Hint Text**: 12px, W400 (placeholder)

---

## Spacing System (8px Grid)

### Component Padding
- **Card Padding**: 18px all sides
- **Section Spacing**: 14px between sections
- **Header Spacing**: 18px V, 20px H
- **Icon Spacing**: 12px H from text

### Internal Spacing
- **Row Gap**: 12px
- **Column Gap**: 6-12px (context dependent)
- **Badge Padding**: 10px H, 5px V
- **Button Padding**: 14px H, 11px V

### External Spacing
- **Card Gap**: 16px (between cards)
- **Tab Gap**: 10px (between tabs)
- **Section Margin**: 16px H (left/right)

---

## Shadow System

### Card Shadow
```
Blur: 12px
Offset: (0, 4)
Dark Mode: 20% opacity
Light Mode: 6% opacity
```

### FAB Shadow
```
Blur: 16px
Offset: (0, 6)
Color: Primary color
Opacity: 35% (dark), 30% (light)
```

### Button Shadow
```
Blur: 8px
Offset: (0, 3)
Color: Button color
Opacity: 30%
```

---

## Responsive Breakpoints

### Mobile (< 600px)
- Cards: Full width - 32px padding
- Tabs: Horizontal scroll enabled
- Icons: 24px size
- Text: Base sizes maintained

### Tablet (600px - 1024px)
- Cards: 2 per row with gap
- Tabs: All visible if space allows
- Icons: 26px size
- Spacing: Increased proportionally

### Desktop (> 1024px)
- Cards: 3 per row with gap
- Tabs: All visible with more spacing
- Icons: 28px size
- Max width constraints applied

---

## Dark Mode Adjustments

```
Light Mode → Dark Mode

Background:
  White → #1C1C1E

Text Primary:
  #1A1A1A → White

Text Secondary:
  70% opacity → 60% opacity

Borders:
  Gray (0.12) → White (0.08)

Shadows:
  4% opacity → 20% opacity
```

---

## Animation Timings

### Tab Selection
- Duration: 300ms
- Curve: easeInOut
- Property: background color, border

### Card Hover (if applicable)
- Duration: 150ms
- Curve: easeOut
- Property: elevation, shadow

### Timer Update
- Duration: 1000ms (1 second)
- Smooth continuous countdown
- Real-time stream updates

---

## Accessibility Checklist

✅ **Color Contrast**
- All text: 4.5:1 minimum ratio
- Buttons: 3:1 minimum ratio

✅ **Touch Targets**
- Minimum: 44x44px (tabs, buttons)
- Actual: 40-48px (optimal)

✅ **Text Readability**
- Minimum font size: 11px (for metadata)
- Optimal sizes: 12-16px (body text)

✅ **Visual Hierarchy**
- Clear distinction between elements
- Proper use of size and weight
- Icons support text labels

---

## Testing Checklist

### Visual Verification
- [ ] Gradient header displays correctly
- [ ] Search pill has proper radius
- [ ] Selected tab is muted green
- [ ] Cards have 20px radius
- [ ] Shadows are subtle and professional
- [ ] Text contrast is sufficient

### Responsive Testing
- [ ] Mobile layout (360px): Proper spacing
- [ ] Tablet layout (600px): Cards centered
- [ ] Desktop layout (1024px): Multi-column
- [ ] Text doesn't overflow
- [ ] Images scale properly

### Theme Testing
- [ ] Dark mode colors accurate
- [ ] Light mode colors accurate
- [ ] Transitions between themes smooth
- [ ] No jank or flickering

### Functional Testing
- [ ] All buttons respond to tap
- [ ] Navigation works
- [ ] Timer updates smoothly
- [ ] Search filters correctly
- [ ] Animations play smoothly

---

This comprehensive design guide ensures consistent implementation across the Teacher Tests Screen. All visual elements follow the established system while maintaining flexibility for future enhancements.
