package com.brewlog.app.domain

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/**
 * Reading and writing recipe files.
 * Matches iOS RecipeFile.swift: decodes single recipe, list of recipes, or { "recipes": [...] }.
 */
object RecipeFile {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        prettyPrint = true
    }

    @Serializable
    private data class Wrapper(val recipes: List<Recipe> = emptyList())

    @Throws(Exception::class)
    fun decode(bytes: ByteArray): List<Recipe> = decode(bytes.decodeToString())

    @Throws(Exception::class)
    fun decode(text: String): List<Recipe> {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) throw IllegalArgumentException("Recipe file is empty.")

        val parsed: List<Recipe> = try {
            val element = json.parseToJsonElement(trimmed)
            when {
                element is kotlinx.serialization.json.JsonArray -> {
                    json.decodeFromJsonElement<List<Recipe>>(element)
                }
                element is kotlinx.serialization.json.JsonObject && element.containsKey("recipes") -> {
                    json.decodeFromJsonElement<Wrapper>(element).recipes
                }
                element is kotlinx.serialization.json.JsonObject -> {
                    listOf(json.decodeFromJsonElement<Recipe>(element))
                }
                else -> emptyList()
            }
        } catch (e: Exception) {
            throw IllegalArgumentException("No recipes found. A recipe file needs valid JSON with at least \"name\" and \"steps\".", e)
        }

        if (parsed.isEmpty()) {
            throw IllegalArgumentException("No recipes found in file.")
        }
        return parsed.take(200).map { it.validated() }
    }

    fun encode(recipes: List<Recipe>): String {
        return if (recipes.size == 1) {
            json.encodeToString(Recipe.serializer(), recipes[0])
        } else {
            json.encodeToString(kotlinx.serialization.builtins.ListSerializer(Recipe.serializer()), recipes)
        }
    }

    const val EXAMPLE_FILE_NAME = "example-recipe-template.json"

    val EXAMPLE_RECIPE_JSON: String = """
{
  "id": "template-custom-v60",
  "name": "My Custom Pour-Over",
  "author": "Home Barista",
  "method": "v60",
  "summary": "Crisp, sweet, and balanced cup with floral aroma and vibrant citrus acidity.",
  "tasteNotes": "Bergamot, jasmine blossoms, honey sweetness and juicy peach.",
  "taste": {
    "acidity": 4,
    "sweetness": 4,
    "body": 3,
    "clarity": 5
  },
  "dose": 15.0,
  "water": 250.0,
  "temperature": 93.0,
  "grind": "Medium-fine (approx. 600–750 µm)",
  "targetTime": 180.0,
  "flowMin": 3.0,
  "flowMax": 6.0,
  "steps": [
    {
      "kind": "bloom",
      "time": 0.0,
      "target": 50.0,
      "note": "Pour evenly and gently swirl to saturate all grounds."
    },
    {
      "kind": "pour",
      "time": 45.0,
      "target": 150.0,
      "note": "Pour in concentric circles from center out."
    },
    {
      "kind": "pour",
      "time": 90.0,
      "target": 250.0,
      "note": "Final gentle pour to target weight; gentle swirl at the end."
    },
    {
      "kind": "remove",
      "time": 180.0,
      "note": "Drawdown finished. Remove dripper and enjoy!"
    }
  ],
  "tips": [
    "Rinse paper filter before adding coffee to wash out paper taste and pre-heat dripper.",
    "Keep kettle spout close to the slurry to minimize turbulent splashing."
  ]
}
""".trimIndent()

    fun fileName(recipes: List<Recipe>): String {
        val base = if (recipes.size == 1) recipes[0].name else "BrewLog recipes"
        val cleaned = base.filter { it.isLetterOrDigit() || it in " -_" }.trim()
        return (if (cleaned.isEmpty()) "Recipe" else cleaned) + ".json"
    }
}

