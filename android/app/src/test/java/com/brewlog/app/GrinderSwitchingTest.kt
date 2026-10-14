package com.brewlog.app

import android.content.SharedPreferences
import com.brewlog.app.data.BrewSetupState
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.EquipmentPreset
import com.brewlog.app.domain.EquipmentType
import com.brewlog.app.domain.GrindUnit
import com.brewlog.app.domain.GrinderSpec
import com.brewlog.app.domain.RecipeLibrary
import com.brewlog.app.domain.TasteFeedback
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class GrinderSwitchingTest {

    private class FakeEditor(private val data: MutableMap<String, Any?>) : SharedPreferences.Editor {
        private val pending = mutableMapOf<String, Any?>()
        private val toRemove = mutableSetOf<String>()

        override fun putString(key: String, value: String?): SharedPreferences.Editor {
            pending[key] = value
            toRemove.remove(key)
            return this
        }

        override fun putStringSet(key: String, values: Set<String>?): SharedPreferences.Editor = this

        override fun putInt(key: String, value: Int): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putLong(key: String, value: Long): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putFloat(key: String, value: Float): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun putBoolean(key: String, value: Boolean): SharedPreferences.Editor {
            pending[key] = value
            return this
        }

        override fun remove(key: String): SharedPreferences.Editor {
            toRemove.add(key)
            pending.remove(key)
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            data.clear()
            pending.clear()
            return this
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        override fun apply() {
            toRemove.forEach { data.remove(it) }
            toRemove.clear()
            data.putAll(pending)
            pending.clear()
        }
    }

    private class FakeSharedPreferences : SharedPreferences {
        private val data = mutableMapOf<String, Any?>()

        override fun getAll(): MutableMap<String, *> = data

        override fun getString(key: String, defValue: String?): String? =
            (data[key] as? String) ?: defValue

        override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? =
            @Suppress("UNCHECKED_CAST") (data[key] as? Set<String>) ?: defValues

        override fun getInt(key: String, defValue: Int): Int =
            (data[key] as? Int) ?: defValue

        override fun getLong(key: String, defValue: Long): Long =
            (data[key] as? Long) ?: defValue

        override fun getFloat(key: String, defValue: Float): Float =
            (data[key] as? Float) ?: defValue

        override fun getBoolean(key: String, defValue: Boolean): Boolean =
            (data[key] as? Boolean) ?: defValue

        override fun contains(key: String): Boolean = data.containsKey(key)

        override fun edit(): SharedPreferences.Editor = FakeEditor(data)

        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}

        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    }

    private val presets by lazy { RecipeLibrary.parse(File("src/main/assets/recipes.json").readText()) }

    @Test
    fun grinderSpecDefaultValuesArePlausible() {
        val comandante = EquipmentPreset.grinders.first { it.name == "Comandante C40" }.makeEquipment()
        val ode = EquipmentPreset.grinders.first { it.name == "Fellow Ode Gen 2" }.makeEquipment()
        val kUltra = EquipmentPreset.grinders.first { it.name == "1Zpresso K-Ultra" }.makeEquipment()
        val timemore = EquipmentPreset.grinders.first { it.name == "Timemore C3" }.makeEquipment()

        assertEquals(24.0, comandante.grinder.defaultStartingValue(), 0.0)
        assertEquals(5.0, ode.grinder.defaultStartingValue(), 0.0)
        assertEquals(7.5, kUltra.grinder.defaultStartingValue(), 0.0)
        assertEquals(16.0, timemore.grinder.defaultStartingValue(), 0.0)
    }

    @Test
    fun defaultStartingValueFallsBackToRangeMidpointOrUnit() {
        val rangeSpec = GrinderSpec(unit = GrindUnit.CLICKS, step = 1.0, rangeNote = "15–25 clicks")
        assertEquals(20.0, rangeSpec.defaultStartingValue(), 0.0)

        val dialSpec = GrinderSpec(unit = GrindUnit.DIAL, step = 0.1)
        assertEquals(5.0, dialSpec.defaultStartingValue(), 0.0)

        val micronSpec = GrinderSpec(unit = GrindUnit.MICRONS, step = 10.0)
        assertEquals(600.0, micronSpec.defaultStartingValue(), 0.0)
    }

    @Test
    fun switchingGrindersDoesNotCarryOverNumber() {
        val prefs = FakeSharedPreferences()
        val setup = BrewSetupState(prefs, presets)

        val comandante = Equipment(id = "c40", name = "Comandante C40", type = EquipmentType.GRINDER,
            grinder = EquipmentPreset.grinders.first { it.name == "Comandante C40" }.grinder ?: GrinderSpec())
        val ode = Equipment(id = "ode2", name = "Fellow Ode Gen 2", type = EquipmentType.GRINDER,
            grinder = EquipmentPreset.grinders.first { it.name == "Fellow Ode Gen 2" }.grinder ?: GrinderSpec())

        // 1. Select Comandante C40: should default to 24.0 clicks
        setup.selectGrinder(comandante.id, comandante, emptyList())
        assertEquals("c40", setup.grinderId)
        assertEquals(24.0, setup.grindValue!!, 0.0)

        // 2. User adjusts Comandante to 26 clicks
        setup.setGrind(26.0)
        assertEquals(26.0, setup.grindValue!!, 0.0)

        // 3. User switches to Fellow Ode Gen 2: MUST NOT carry over 26 clicks!
        setup.selectGrinder(ode.id, ode, emptyList())
        assertEquals("ode2", setup.grinderId)
        assertNotEquals(26.0, setup.grindValue)
        assertEquals(5.0, setup.grindValue!!, 0.0) // Ode's default starting dial

        // 4. User adjusts Ode to dial 6.0
        setup.setGrind(6.0)
        assertEquals(6.0, setup.grindValue!!, 0.0)

        // 5. User switches back to Comandante: should remember 26 clicks, NOT Ode's 6.0!
        setup.selectGrinder(comandante.id, comandante, emptyList())
        assertEquals("c40", setup.grinderId)
        assertNotEquals(6.0, setup.grindValue)
        assertEquals(26.0, setup.grindValue!!, 0.0)

        // 6. User switches back to Ode: should remember 6.0, NOT Comandante's 26.0!
        setup.selectGrinder(ode.id, ode, emptyList())
        assertEquals("ode2", setup.grinderId)
        assertNotEquals(26.0, setup.grindValue)
        assertEquals(6.0, setup.grindValue!!, 0.0)

        // 7. Switching to null (no grinder) clears the numeric value
        setup.selectGrinder(null, null, emptyList())
        assertNull(setup.grinderId)
        assertNull(setup.grindValue)
    }

    @Test
    fun switchingToGrinderWithHistoryUsesHistoryIfNeverExplicitlySetInSetup() {
        val prefs = FakeSharedPreferences()
        val setup = BrewSetupState(prefs, presets)

        val kUltra = Equipment(id = "k-ultra", name = "1Zpresso K-Ultra", type = EquipmentType.GRINDER,
            grinder = EquipmentPreset.grinders.first { it.name == "1Zpresso K-Ultra" }.grinder ?: GrinderSpec())

        val history = listOf(
            Brew(id = "b1", grinderId = "k-ultra", recipeId = setup.recipe.id, grindValue = 7.8,
                rating = 5, feedback = setOf(TasteFeedback.PERFECT), date = System.currentTimeMillis() - 1000)
        )

        // Select K-Ultra: never set in setup yet, but has history with reference rating -> should use 7.8
        setup.selectGrinder(kUltra.id, kUltra, history)
        assertEquals(7.8, setup.grindValue!!, 0.0)

        // User explicitly sets to 8.0
        setup.setGrind(8.0)
        assertEquals(8.0, setup.grindValue!!, 0.0)

        // Switch away and back -> should remember the explicit 8.0
        val c40 = Equipment(id = "c40", name = "Comandante C40", type = EquipmentType.GRINDER,
            grinder = EquipmentPreset.grinders.first { it.name == "Comandante C40" }.grinder ?: GrinderSpec())
        setup.selectGrinder(c40.id, c40, history)
        assertEquals(24.0, setup.grindValue!!, 0.0)

        setup.selectGrinder(kUltra.id, kUltra, history)
        assertEquals(8.0, setup.grindValue!!, 0.0)
    }

    @Test
    fun remembersGrindAcrossInstancesViaPreferences() {
        val prefs = FakeSharedPreferences()
        val setup1 = BrewSetupState(prefs, presets)

        val ode = Equipment(id = "ode2", name = "Fellow Ode Gen 2", type = EquipmentType.GRINDER,
            grinder = EquipmentPreset.grinders.first { it.name == "Fellow Ode Gen 2" }.grinder ?: GrinderSpec())

        setup1.selectGrinder(ode.id, ode, emptyList())
        setup1.setGrind(5.3)

        // Create a new BrewSetupState instance simulating app restart with the same prefs
        val setup2 = BrewSetupState(prefs, presets)
        assertEquals("ode2", setup2.grinderId)
        assertEquals(5.3, setup2.grindValue!!, 0.01)
    }
}
