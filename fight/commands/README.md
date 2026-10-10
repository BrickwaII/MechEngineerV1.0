# fight/commands/

Player input as plain data (M4). Mouse, keyboard and tests all go through here.

- `FightCommand`: select bot, select skill, select target, wait, cancel.
- `FightCommandHandler`: applies commands to a `Fight`, holds the selection
  (bot, then skill, then target), and plays enemy turns with a `FightPolicy`.
  `apply()` returns "" or why the command was refused; a refused command
  changes nothing.

      var handler := FightCommandHandler.new(Fight.new(request, seed))
      handler.apply(FightCommand.select_skill("strike"))
      handler.apply(FightCommand.select_target("scrap_drone#1"))

Only the pending unit acts (ATB wait mode). Any living bot may be selected to
look at it. A bare `wait()` charges for the selected skill, else the cheapest
skill the bot cannot afford yet.
