-- Audited feature switches (all enabled after 48a0f14 game-thread fix). Restart the game after edits. No Saved/vanilla files required.
-- settings.json.features can also disable a group; false here always takes precedence.
return {
    features={sync=true,physics=true,possession=true,cauldronOffset=true,extras=true,creative=true,ui=true},
    -- Runtime InitGameState/world events, LoadMap and concrete birth guards remain active. Extra native UFunction travel hooks
    -- are opt-in: ClientTravelInternal marshals FGuid before our Lua callback runs.
    nativeTravelHooks=false,
}
