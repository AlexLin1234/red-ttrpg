import { expect, test, type Page } from '@playwright/test'

/**
 * The cross-screen flow a GM actually walks: open a save, read the city, run a
 * round on the board, edit an NPC, save. Screenshots land in
 * e2e/__screenshots__ so each screen can be compared against docs/mockups.
 */

const SHOTS = 'e2e/__screenshots__'

async function openCampaign(page: Page) {
  await page.goto('/')
  await page.waitForSelector('.library-row')
  await page.getByRole('button', { name: /Continue/ }).click()
  await expect(page.locator('.city-map')).toBeVisible()
}

async function goTo(page: Page, screen: 'Library' | 'City' | 'Location' | 'Forge') {
  await page.locator('.app-nav-item', { hasText: new RegExp(`^${screen}`, 'i') }).first().click()
}

test('the library lists saves and reports real file facts', async ({ page }) => {
  await page.goto('/')
  await page.waitForSelector('.library-row')

  await expect(page.locator('.library-row')).toHaveCount(6)
  await expect(page.locator('.library-title')).toHaveText('Blackwall Sunrise')

  // Integrity is a checksum comparison, not a decoration.
  await expect(page.locator('.library-facts')).toContainText('Verified')
  await expect(page.locator('.library-facts')).toContainText('.RED v0.4')
  await expect(page.locator('.library-path')).toContainText('.red')
  await expect(page.locator('.library-party-card')).toHaveCount(4)

  await page.screenshot({ path: `${SHOTS}/1a-library.png` })
})

test('the city map inspects districts and advances the clock', async ({ page }) => {
  await openCampaign(page)

  await page.locator('.city-district').filter({ hasText: 'WATSON' }).first().hover()
  await expect(page.locator('.city-detail-name')).toHaveText('Watson')
  await expect(page.locator('.city-detail')).toContainText('Maelstrom')

  const before = await page.locator('.city-time').textContent()
  await page.getByRole('button', { name: '+1 hour' }).click()
  await expect(page.locator('.city-time')).not.toHaveText(before ?? '')

  // Editing campaign state marks the save dirty.
  await expect(page.locator('.app-dirty')).toHaveText(/Unsaved changes/i)

  await page.locator('.city-district').filter({ hasText: 'PACIFICA' }).first().hover()
  await expect(page.locator('.city-detail-name')).toHaveText('Pacifica')
  await page.screenshot({ path: `${SHOTS}/1b-city.png` })
})

test('the board rolls initiative and resolves a shot through the cover prompt', async ({ page }) => {
  await openCampaign(page)
  await goTo(page, 'Location')
  await expect(page.locator('.loc-canvas')).toBeVisible()

  await page.getByRole('button', { name: 'Roll initiative' }).click()
  await expect(page.locator('.loc-init-row')).toHaveCount(6)
  await expect(page.locator('.loc-bar')).toContainText('Round 1')

  // Pick the first combatant off the initiative rail, then shoot the last one.
  await page.locator('.loc-init-row').first().click()
  await page.getByRole('button', { name: 'Fire', exact: true }).click()

  const canvas = page.locator('.loc-canvas')
  const box = (await canvas.boundingBox())!

  // Sweep the board for a unit to shoot; the token positions are projected
  // through a 3D camera, so a fixed pixel would be brittle.
  let fired = false
  for (let column = 0; column <= 12 && !fired; column += 1) {
    for (let row = 0; row <= 8 && !fired; row += 1) {
      await page.mouse.click(
        box.x + (box.width * (column + 0.5)) / 13,
        box.y + (box.height * (row + 0.5)) / 9,
      )
      await page.waitForTimeout(60)
      if ((await page.locator('.loc-modal').count()) > 0) fired = true
      else if ((await page.locator('.loc-card.tone-hit, .loc-card.tone-miss').count()) > 0) {
        fired = true
      }
    }
  }
  expect(fired, 'expected a click on the board to hit a unit').toBe(true)

  if (await page.locator('.loc-modal').isVisible()) {
    await expect(page.locator('.loc-modal-title')).toBeVisible()
    await page.screenshot({ path: `${SHOTS}/1c-cover-prompt.png` })
    await page.getByRole('button', { name: /Cover takes the hit/ }).click()
  }

  // The resolution card writes the arithmetic out longhand.
  const card = page.locator('.loc-card').first()
  await expect(card).toBeVisible()
  await expect(card).toContainText(/Attack: base/)
  await expect(page.locator('.loc-card-title')).toHaveText(/HIT|MISS|STOPPED|CRITICAL INJURY/)

  // Undo is exact, not approximate.
  await page.getByRole('button', { name: 'Undo' }).click()
  await expect(page.locator('.loc-card-title')).toHaveText('UNDO')

  await page.screenshot({ path: `${SHOTS}/1c-location.png` })
})

test('the blast tool announces an area effect', async ({ page }) => {
  await openCampaign(page)
  await goTo(page, 'Location')
  await page.getByRole('button', { name: 'Blast' }).click()
  await expect(page.locator('.loc-banner')).toContainText('no cover save')

  const box = (await page.locator('.loc-canvas').boundingBox())!
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
  await expect(page.locator('.loc-card')).toContainText(/blast 6 m|caught nobody/)
})

test('the forge edits a sheet and saves cover into the board palette', async ({ page }) => {
  await openCampaign(page)
  await goTo(page, 'Forge')

  await expect(page.locator('.forge-roster-row')).not.toHaveCount(0)
  await page.locator('.forge-roster-row').filter({ hasText: 'Nine-Volt' }).click()
  await expect(page.locator('.forge-name')).toHaveValue(/Nine-Volt/)

  // Six hit locations, and the ablated ones are called out.
  await expect(page.locator('.forge-armor-slot')).toHaveCount(6)
  await expect(page.locator('.forge-armor-slot.is-ablated')).not.toHaveCount(0)

  await page.getByRole('button', { name: 'Skills' }).click()
  await expect(page.locator('.forge-skill').first()).toContainText('Handgun')

  await page.getByRole('button', { name: 'Gear' }).click()
  await expect(page.locator('.forge-gear')).toContainText('HUM')

  await page.screenshot({ path: `${SHOTS}/1d-forge.png` })

  // Cover built here shows up in the board's PROPS palette.
  const paletteCount = Number((await page.locator('.section-head >> text=/in palette/').textContent())?.match(/\d+/)?.[0] ?? 0)
  await page.getByRole('button', { name: 'Steel Plate' }).click()
  await page.getByRole('button', { name: 'Save to palette' }).click()

  await goTo(page, 'Location')
  await page.getByRole('button', { name: 'props' }).click()
  await expect(page.locator('.loc-chip')).toHaveCount(paletteCount + 1)
})

test('a random mook joins the roster and the campaign saves', async ({ page }) => {
  await openCampaign(page)
  await goTo(page, 'Forge')

  const before = await page.locator('.forge-roster-row').count()
  await page.getByRole('button', { name: 'Roll random mook' }).click()
  await expect(page.locator('.forge-roster-row')).toHaveCount(before + 1)

  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page.locator('.app-dirty')).toHaveText('Saved')

  // The write went through the container, so reopening finds the new mook.
  await goTo(page, 'Library')
  await page.getByRole('button', { name: /Continue/ }).click()
  await goTo(page, 'Forge')
  await expect(page.locator('.forge-roster-row')).toHaveCount(before + 1)
})
