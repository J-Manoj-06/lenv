# Daily Challenge - Quick Start Guide

## 🚀 What's New?

The Daily Challenge feature now uses **OpenTriviaDB API** to fetch real trivia questions tailored to each student's academic level!

---

## ✨ Key Features

### 🎯 One Challenge Per Day
- Students get exactly ONE trivia question every day
- Once answered (correct or wrong), challenge is **LOCKED** until tomorrow
- No way to cheat or get multiple attempts

### 📚 Smart Question Selection
Questions are automatically selected based on student's class:

- **Class 1-4**: Easy questions about General Knowledge & Science
- **Class 5-8**: Easy questions about Computers, Geography & History
- **Class 9-10**: Medium questions about Science, Computers & Math
- **Class 11-12**: Mixed difficulty (30% easy, 50% medium, 20% hard) across all subjects

### 🎁 Rewards
- **Correct Answer**: +5 Reward Points ⭐
- **Incorrect Answer**: Try again tomorrow!
- **Streak Tracking**: Build daily streaks for consistency

### 🎨 Beautiful UI
- Gamified card design with animations
- Color-coded by subject category
- Success/failure result screen with motivational messages
- Particle effects and smooth transitions

---

## 📍 Where to Find It

The Daily Challenge card appears on the **Student Dashboard** between the Points Card and Active Tests section.

---

## 🎮 How It Works

### First Time Today
1. Open student dashboard
2. See the Daily Challenge card with today's question
3. Read the question carefully
4. Select one of the four options
5. Click "Submit Answer"
6. See animated result screen
7. Earn points if correct!

### Already Answered Today
- Card shows your result (correct/incorrect)
- Displays points earned
- Shows your current streak
- Message: "Come back tomorrow for next challenge!"

### Tomorrow
- New challenge automatically appears at midnight
- Previous day's result is archived
- Streak continues if you answered yesterday

---

## 🔧 Technical Details

### API Source
- **OpenTriviaDB**: https://opentdb.com/
- Free, open-source trivia API
- Thousands of questions across categories

### Storage
- **SharedPreferences**: Local caching for instant display
- **Firebase Firestore**: Answer records and points tracking
- **Per-user isolation**: Each student's data is separate

### Question Flow
1. Check if challenge exists for today
2. If not, fetch from OpenTriviaDB based on student's class
3. Decode HTML entities (`&quot;` → `"`)
4. Shuffle answer options randomly
5. Cache locally for fast loading
6. Save to SharedPreferences and Firebase

---

## 🐛 Troubleshooting

### "Unable to load challenge"
**Cause**: Network issue or API timeout  
**Solution**: Check internet connection, tap "Retry" button

### Challenge not updating daily
**Cause**: Date/time mismatch  
**Solution**: Ensure device date/time is set to automatic

### Answered but still showing question
**Cause**: Cache sync issue  
**Solution**: Pull to refresh dashboard or restart app

### Wrong difficulty for my class
**Cause**: Student's standard/class not set in profile  
**Solution**: Update profile with correct class information

---

## 🎯 Best Practices

### For Students
- Answer the challenge early in the day
- Build a daily streak for consistency
- Read questions carefully before selecting
- Learn from incorrect answers

### For Teachers
- Encourage students to participate daily
- Track overall class participation
- Use as a fun icebreaker activity
- Consider bonus points for long streaks

### For Admins
- Monitor API usage to stay within rate limits
- Check error logs for failed requests
- Consider caching strategies for high traffic
- Backup answer records regularly

---

## 📊 Analytics & Insights

### Available Metrics
- Daily participation rate
- Correct answer percentage
- Average streak length
- Most missed questions
- Category performance

### Firebase Collections
```
daily_challenge_answers/
  {studentId}_{date}:
    - studentId
    - studentEmail
    - date
    - selectedAnswer
    - correctAnswer
    - isCorrect
    - answeredAt

student_rewards/
  {rewardId}:
    - studentId
    - testId: "daily_challenge_{date}"
    - pointsEarned: 5
    - source: "daily_challenge"
    - timestamp
```

---

## 🔮 Future Enhancements

### Planned Features
- [ ] Weekly leaderboards
- [ ] Subject-specific challenges
- [ ] Bonus streak rewards (7-day, 30-day)
- [ ] Challenge history viewer
- [ ] Social sharing of results
- [ ] Custom teacher questions
- [ ] Multiplayer challenge mode
- [ ] Time-based difficulty adjustment

### Community Requests
- [ ] Allow challenge retake after 12 hours
- [ ] Hint system (costs points)
- [ ] Explanation for correct answers
- [ ] Category preference selection
- [ ] Challenge reminders/notifications

---

## 🤝 Support

### Getting Help
- Check this guide first
- Review error messages carefully
- Test with multiple students
- Check Firebase logs
- Contact development team

### Reporting Issues
Include:
- Student ID
- Date/time of issue
- Screenshot of error
- Steps to reproduce
- Device/browser info

---

## ✅ Testing Checklist

Before deployment, verify:
- [ ] Questions fetch correctly
- [ ] Answers shuffle randomly
- [ ] Only one challenge per day
- [ ] Challenge locks after answering
- [ ] Points awarded correctly
- [ ] Result screen displays
- [ ] New challenge appears tomorrow
- [ ] User switch works correctly
- [ ] Error handling functional
- [ ] Animations smooth

---

## 🎉 Success Metrics

### Week 1 Goals
- 70% student participation
- 60% correct answer rate
- Average 3-day streak

### Month 1 Goals
- 85% student participation
- 65% correct answer rate
- 10+ students with 30-day streak

---

**Feature Status**: ✅ Production Ready  
**Last Updated**: December 2, 2025  
**Version**: 1.0.0
